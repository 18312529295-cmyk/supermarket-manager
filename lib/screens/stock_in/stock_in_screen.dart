import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/product.dart';
import '../../models/stock_record.dart';
import '../../services/database_service.dart';
import '../../utils/product_detail_dialog.dart';
import '../../widgets/common/barcode_scanner.dart';

class StockInScreen extends StatefulWidget {
  const StockInScreen({super.key});

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  final List<_StockInItem> _sessionItems = [];  // 本次会话入库记录
  List<Map<String, dynamic>> _historyRecords = [];  // 历史入库记录（从DB加载）
  bool _batchMode = true;
  bool _isHandlingBarcode = false;  // ★ 防止重复弹窗的标志
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// 加载入库历史记录
  Future<void> _loadHistory() async {
    try {
      final records = await DatabaseService.instance.getStockRecordsWithName(type: StockType.inBound);
      if (mounted) {
        setState(() {
          _historyRecords = records;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanBarcode() async {
    _scannerController = MobileScannerController();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: '扫码入库',
          continuous: _batchMode,
          externalController: _scannerController,
          onScan: (barcode, format) {
            if (!_batchMode) {
              Navigator.pop(context, barcode);
            } else {
              _handleBarcode(barcode);
            }
          },
        ),
      ),
    );
    _scannerController?.dispose();
    _scannerController = null;
    if (result != null && !_batchMode) {
      await _handleBarcode(result);
    }
  }

  /// ★ 防重复处理：如果正在处理一个条码，忽略新的扫码回调
  Future<void> _handleBarcode(String barcode) async {
    if (_isHandlingBarcode) return;
    _isHandlingBarcode = true;
    _scannerController?.stop();

    try {
      final provider = context.read<InventoryProvider>();
      final product = await provider.findProductByBarcode(barcode);

      if (product != null) {
        if (product.priceCny == 0) {
          await _showPresetProductForm(product);
        } else {
          await _showQuantityDialog(product);
        }
      } else {
        await _showCreateProductDialog(barcode);
      }
    } catch (e) {
      debugPrint('[StockIn] _handleBarcode error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫码处理失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _isHandlingBarcode = false;
      if (mounted && _scannerController != null) {
        try { _scannerController!.start(); } catch (_) {}
      }
    }
  }

  /// 数量确认弹窗 — 确认后立即写入DB
  /// ★ v6.31 修复：默认以普通单位显示，用户可手动切换到复合模式
  Future<void> _showQuantityDialog(Product product) async {
    // ★ 默认普通单位，不自动进入复合模式
    final useComposite = false;
    final bigQtyController = TextEditingController(text: '1');
    final smallQtyController = TextEditingController(text: '0');
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();
    final expiryController = TextEditingController();
    final minStockController = TextEditingController(text: '10');

    // 复合单位设置控制器（用于修改已有设定）
    final unitBigController = TextEditingController(text: product.unitBig ?? '');
    final unitSmallController = TextEditingController(text: product.unitSmall ?? '');
    final unitRatioController = TextEditingController(text: product.unitRatio?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 计算总小单位数量
          int getTotalQty() {
            if (useComposite) {
              final big = int.tryParse(bigQtyController.text) ?? 0;
              final small = int.tryParse(smallQtyController.text) ?? 0;
              return product.toTotalSmallQty(big, small);
            }
            return int.tryParse(qtyController.text) ?? 0;
          }

          final totalQty = getTotalQty();
          final displayQty = useComposite ? product.formatCompositeQtyDetail(totalQty) : '$totalQty${product.unit ?? "件"}';

          return AlertDialog(
            title: Text(product.nameCn),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('条码: ${product.barcode}', style: const TextStyle(fontSize: 12)),
                  if (product.nameRu != null)
                    Text(product.nameRu!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),

                  // ★ 复合单位输入区域
                  if (useComposite) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bigQtyController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '${product.unitBig}数',
                              prefixIcon: const Icon(Icons.inventory_2),
                              helperText: '1${product.unitBig}=${product.unitRatio}${product.unitSmall}',
                            ),
                            autofocus: true,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('+', style: TextStyle(fontSize: 20, color: Colors.grey.shade400)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: smallQtyController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '${product.unitSmall}数',
                              prefixIcon: const Icon(Icons.format_list_numbered),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                      ],
                    ),
                    // 实时数量预览
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        '合计: $displayQty',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // ★ 切换回普通单位
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        // ★ v6.31 fix: copyWith(null) 不会清除字段(??语义)，直接用DB更新
                        await DatabaseService.instance.clearProductCompositeUnit(product.id!);
                        final cleared = product.copyWith(unitBig: null, unitSmall: null, unitRatio: null);
                        Navigator.pop(ctx);
                        _showQuantityDialog(cleared);
                      },
                      child: const Text('切换回普通单位'),
                    ),
                  ] else ...[
                    // ★ 普通单位输入
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '入库数量（${product.unit ?? "件"}）',
                        prefixIcon: const Icon(Icons.format_list_numbered),
                      ),
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    // ★ 复合单位设置按钮 — 更醒目
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.inventory_2, size: 18, color: Colors.blue.shade600),
                        label: Text(
                          product.unitBig != null && product.unitSmall != null && product.unitRatio != null
                              ? '修改复合单位 (1${product.unitBig}=${product.unitRatio}${product.unitSmall})'
                              : '设置箱/瓶等复合单位',
                          style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.blue.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          _showUnitSettingsDialog(product,
                            unitBigController: unitBigController,
                            unitSmallController: unitSmallController,
                            unitRatioController: unitRatioController,
                            onSave: (big, small, ratio) async {
                              final updated = product.copyWith(
                                unitBig: big,
                                unitSmall: small,
                                unitRatio: ratio,
                              );
                              await context.read<InventoryProvider>().updateProduct(updated);
                              Navigator.pop(ctx);
                              _showQuantityDialog(updated);
                            },
                            );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextField(
                    controller: expiryController,
                    decoration: const InputDecoration(labelText: '保质期至 (建议填写)', prefixIcon: Icon(Icons.calendar_today)),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 180)),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (date != null) {
                        expiryController.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '备注', prefixIcon: Icon(Icons.note)),
                  ),
                  const SizedBox(height: 12),
                  // ★ 低库存预警阈值设置
                  TextField(
                    controller: minStockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '低库存预警线 (可选)',
                      prefixIcon: Icon(Icons.warning_amber),
                      helperText: '库存低于此数量时会在看板预警',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                onPressed: () async {
                  if (totalQty <= 0) return;

                  final appProvider = context.read<AppProvider>();
                  final inventoryProvider = context.read<InventoryProvider>();
                  final expiryDate = expiryController.text.isNotEmpty ? DateTime.parse(expiryController.text) : null;

                  final record = StockRecord(
                    productId: product.id!,
                    barcode: product.barcode,
                    type: StockType.inBound,
                    quantity: totalQty,
                    priceCny: product.priceCny,
                    priceUzs: product.priceUzs,
                    operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
                    note: noteController.text.isNotEmpty ? noteController.text : null,
                    expiryDate: expiryDate,
                  );

                  await inventoryProvider.recordStockIn(record);

                  // ★ 更新低库存预警阈值
                  final minStock = int.tryParse(minStockController.text);
                  if (minStock != null && minStock >= 0) {
                    await DatabaseService.instance.updateInventoryMinStock(product.id!, minStock);
                  }

                  setState(() {
                    _sessionItems.add(_StockInItem(product: product, quantity: totalQty, expiryDate: expiryDate));
                  });

                  Navigator.pop(ctx);
                  _loadHistory();

                  if (mounted) {
                    final qtyDisplay = useComposite ? product.formatCompositeQtyDetail(totalQty) : '$totalQty${product.unit ?? "件"}';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已入库: ${product.nameCn} x$qtyDisplay'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
                    );
                  }
                },
                child: const Text('确认入库'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ★ v6.31: 统一复合单位预设列表（供入库和 _UnitPresetPicker 共用）
  static const List<Map<String, dynamic>> unitPresets = [
    {'big': '箱', 'small': '罐', 'ratio': 36},
    {'big': '箱', 'small': '瓶', 'ratio': 24},
    {'big': '箱', 'small': '瓶', 'ratio': 12},
    {'big': '箱', 'small': '瓶', 'ratio': 6},
    {'big': '箱', 'small': '包', 'ratio': 20},
    {'big': '箱', 'small': '包', 'ratio': 10},
    {'big': '箱', 'small': '盒', 'ratio': 24},
    {'big': '箱', 'small': '盒', 'ratio': 12},
    {'big': '箱', 'small': '袋', 'ratio': 20},
    {'big': '箱', 'small': '袋', 'ratio': 10},
    {'big': '箱', 'small': '个', 'ratio': 12},
    {'big': '箱', 'small': '罐', 'ratio': 24},
    {'big': '箱', 'small': '罐', 'ratio': 12},
    {'big': '条', 'small': '包', 'ratio': 10},
    {'big': '条', 'small': '包', 'ratio': 5},
    {'big': '打', 'small': '瓶', 'ratio': 12},
    {'big': '打', 'small': '罐', 'ratio': 12},
    {'big': '提', 'small': '包', 'ratio': 6},
    {'big': '提', 'small': '卷', 'ratio': 10},
  ];

  /// 复合单位设置弹窗 — 带预置单位选择和自定义
  void _showUnitSettingsDialog(Product product, {
    required TextEditingController unitBigController,
    required TextEditingController unitSmallController,
    required TextEditingController unitRatioController,
    required Function(String big, String small, int ratio) onSave,
  }) {
    int? selectedPreset;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.inventory_2, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('设置复合单位', style: TextStyle(fontSize: 16))),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择常用单位组合，或自定义输入', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),

                  // ★ 预置单位选择（Wrap布局）
                  const Text('常用组合:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(unitPresets.length, (index) {
                      final preset = unitPresets[index];
                      final isSelected = selectedPreset == index;
                      final label = '1${preset['big'] as String}=${preset['ratio']}${preset['small'] as String}';
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedPreset = index;
                            unitBigController.text = preset['big'] as String;
                            unitSmallController.text = preset['small'] as String;
                            unitRatioController.text = '${preset['ratio']}';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : Colors.grey.shade800,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('自定义输入:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  // 大单位名称（带预设选择）
                  TextField(
                    controller: unitBigController,
                    decoration: const InputDecoration(
                      labelText: '大单位名称',
                      hintText: '例如：箱',
                      prefixIcon: Icon(Icons.inventory_2),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() { selectedPreset = null; }),
                  ),
                  const SizedBox(height: 12),
                  // 小单位名称
                  TextField(
                    controller: unitSmallController,
                    decoration: const InputDecoration(
                      labelText: '小单位名称',
                      hintText: '例如：瓶',
                      prefixIcon: Icon(Icons.format_list_numbered),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() { selectedPreset = null; }),
                  ),
                  const SizedBox(height: 12),
                  // 换算比率
                  TextField(
                    controller: unitRatioController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '换算比率',
                      hintText: '例如：24',
                      prefixIcon: Icon(Icons.calculate),
                      helperText: '1大单位 = 多少小单位',
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() { selectedPreset = null; }),
                  ),
                  const SizedBox(height: 8),
                  // 实时预览
                  if (unitBigController.text.isNotEmpty && unitSmallController.text.isNotEmpty && unitRatioController.text.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '1${unitBigController.text} = ${unitRatioController.text}${unitSmallController.text}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              // ★ 返回按钮
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('返回'),
              ),
              ElevatedButton(
                onPressed: () {
                  final big = unitBigController.text.trim();
                  final small = unitSmallController.text.trim();
                  final ratio = int.tryParse(unitRatioController.text) ?? 0;
                  if (big.isEmpty || small.isEmpty || ratio <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('请选择或输入完整的单位和换算比率')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  onSave(big, small, ratio);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateProductDialog(String barcode) async {
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('商品不存在'),
        content: Text('条码 $barcode 未找到，是否新增商品？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('新增商品'),
          ),
        ],
      ),
    );
    if (shouldCreate == true) {
      await _showNewProductForm(barcode);
    }
  }

  Future<void> _showPresetProductForm(Product product) async {
    final nameCnController = TextEditingController(text: product.nameCn);
    final foreignNameController = TextEditingController(text: product.foreignName ?? '');
    final categoryController = TextEditingController(text: product.category);
    final supplierController = TextEditingController(text: product.supplier ?? '');

    late Product updatedProduct;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.local_offer, color: Colors.orange), const SizedBox(width: 8), const Expanded(child: Text('预置商品，请补充信息'))]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('条码: ${product.barcode}', style: const TextStyle(fontSize: 12)),
                  if (product.supplier != null && product.supplier!.isNotEmpty)
                    Text('品牌: ${product.supplier}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(controller: nameCnController, decoration: const InputDecoration(labelText: '中文名称 *')),
              TextField(controller: foreignNameController, decoration: const InputDecoration(labelText: '外语名称')),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: '品类 *')),
              TextField(controller: supplierController, decoration: const InputDecoration(labelText: '品牌/供应商')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存并入库'),
            onPressed: () async {
              if (nameCnController.text.isEmpty || categoryController.text.isEmpty) return;
              updatedProduct = product.copyWith(
                nameCn: nameCnController.text,
                foreignName: foreignNameController.text.isNotEmpty ? foreignNameController.text : null,
                nameRu: null,
                nameUz: null,
                category: categoryController.text,
                supplier: supplierController.text.isNotEmpty ? supplierController.text : null,
              );
              await context.read<InventoryProvider>().updateProduct(updatedProduct);
              Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );
    if (saved == true) {
      await _showQuantityDialog(updatedProduct);
    }
  }

  Future<void> _showNewProductForm(String barcode) async {
    final nameCnController = TextEditingController();
    final foreignNameController = TextEditingController();
    final categoryController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final expiryController = TextEditingController();
    final noteController = TextEditingController();
    final bigQtyController = TextEditingController(text: '1');
    final smallQtyController = TextEditingController(text: '0');
    // ★ 用Map捕获最终复合单位状态（对话框关闭后读取）
    final compositeState = <String, dynamic>{'use': false, 'big': '箱', 'small': '瓶', 'ratio': 24};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool _use = compositeState['use'] as bool;
          String _big = compositeState['big'] as String;
          String _small = compositeState['small'] as String;
          int _ratio = compositeState['ratio'] as int;
          int getTotalQty() {
            if (_use) {
              final big = int.tryParse(bigQtyController.text) ?? 0;
              final small = int.tryParse(smallQtyController.text) ?? 0;
              return big * _ratio + small;
            }
            return int.tryParse(qtyController.text) ?? 0;
          }
          final totalQty = getTotalQty();
          final totalDisplay = _use
              ? '$totalQty$_small（${bigQtyController.text}$_big${smallQtyController.text}$_small）'
              : '$totalQty 件';

          return AlertDialog(
            title: const Text('新增商品并入库'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('条码: $barcode', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(controller: nameCnController, decoration: const InputDecoration(labelText: '中文名称 *'), autofocus: true),
                TextField(controller: foreignNameController, decoration: const InputDecoration(labelText: '外语名称')),
                TextField(controller: categoryController, decoration: const InputDecoration(labelText: '品类 *')),
                const Divider(height: 24),

                // ★ 复合单位开关
                if (!_use)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.inventory_2, size: 18, color: Colors.blue),
                      label: const Text('设置箱/瓶等复合单位', style: TextStyle(fontSize: 13)),
                      onPressed: () => setDialogState(() { compositeState['use'] = true; }),
                    ),
                  ),

                // ★ 复合单位输入
                if (_use) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bigQtyController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: '${_big}数', prefixIcon: const Icon(Icons.inventory_2), helperText: '1$_big=$_ratio$_small'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('+', style: TextStyle(fontSize: 20, color: Colors.grey.shade400)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: smallQtyController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: '${_small}数', prefixIcon: const Icon(Icons.format_list_numbered)),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.settings, size: 14),
                    label: const Text('修改单位设置'),
                    onPressed: () async {
                      // 弹出单位预置选取
                      final result = await showDialog<Map<String, dynamic>>(
                        context: ctx,
                        builder: (c) => _UnitPresetPicker(),
                      );
                      if (result != null) {
                        setDialogState(() {
                          compositeState['big'] = result['big'] as String;
                          compositeState['small'] = result['small'] as String;
                          compositeState['ratio'] = result['ratio'] as int;
                        });
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () => setDialogState(() { compositeState['use'] = false; }),
                    child: const Text('取消复合单位', style: TextStyle(fontSize: 12)),
                  ),
                ] else ...[
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '入库数量 *', prefixIcon: Icon(Icons.format_list_numbered)),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],

                // ★ 总量预览
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '合计入库: $totalDisplay',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.blue),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: expiryController,
                  decoration: const InputDecoration(labelText: '保质期至 (选填)', prefixIcon: Icon(Icons.calendar_today)),
                  readOnly: true,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx, initialDate: DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (date != null) expiryController.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  },
                ),
                TextField(controller: noteController, decoration: const InputDecoration(labelText: '备注', prefixIcon: Icon(Icons.note))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                onPressed: () async {
                  final n = nameCnController.text.trim();
                  final c = categoryController.text.trim();
                  final qty = totalQty;
                  if (n.isEmpty || c.isEmpty) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请填写名称和品类'))); return; }
                  if (qty <= 0) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入数量'))); return; }
                  Navigator.pop(ctx, true); // 确认创建
                },
                child: const Text('保存并入库'),
              ),
            ],
          );
        },
      ),
    );

    // ★ v6.31: 用户点了"取消"则不执行创建
    if (confirmed != true) return;

    // ★ 弹窗关闭后执行数据库操作
    final n = nameCnController.text.trim();
    final c = categoryController.text.trim();
    final finalUse = compositeState['use'] as bool;
    final finalBig = compositeState['big'] as String;
    final finalSmall = compositeState['small'] as String;
    final finalRatio = compositeState['ratio'] as int;
    final qty = finalUse ? getTotalQtyLocal(bigQtyController, smallQtyController, finalRatio) : int.tryParse(qtyController.text) ?? 0;
    if (n.isEmpty || c.isEmpty || qty <= 0 || !mounted) return;

    try {
      final provider = context.read<InventoryProvider>();
      final appProvider = context.read<AppProvider>();
      final expiryDate = expiryController.text.isNotEmpty ? DateTime.tryParse(expiryController.text) : null;

      final product = Product(
        barcode: barcode, nameCn: n,
        foreignName: foreignNameController.text.trim().isNotEmpty ? foreignNameController.text.trim() : null,
        nameRu: null, nameUz: null,
        category: c, priceCny: 0, priceUzs: 0,
        unitBig: finalUse ? finalBig : null,
        unitSmall: finalUse ? finalSmall : null,
        unitRatio: finalUse ? finalRatio : null,
      );
      final id = await provider.addProduct(product);
      final newProduct = product.copyWith(id: id);

      final record = StockRecord(
        productId: id, barcode: barcode, type: StockType.inBound, quantity: qty,
        priceCny: 0, priceUzs: 0,
        operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
        note: noteController.text.isNotEmpty ? noteController.text : null,
        expiryDate: expiryDate,
      );
      await provider.recordStockIn(record);

      if (mounted) {
        final qtyDisplay = finalUse ? '$qty$finalSmall（${bigQtyController.text}$finalBig${smallQtyController.text}$finalSmall）' : '$qty 件';
        setState(() => _sessionItems.add(_StockInItem(product: newProduct, quantity: qty, expiryDate: expiryDate)));
        _loadHistory();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已入库: $n x$qtyDisplay'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('入库失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  int getTotalQtyLocal(TextEditingController bigCtrl, TextEditingController smallCtrl, int ratio) {
    final big = int.tryParse(bigCtrl.text) ?? 0;
    final small = int.tryParse(smallCtrl.text) ?? 0;
    return big * ratio + small;
  }

  /// ★ v6.10: 监听同步版本号，同步完成后自动刷新历史列表
  int _lastSyncVersion = 0;

  @override
  Widget build(BuildContext context) {
    final syncVersion = context.watch<InventoryProvider>().syncVersion;
    if (_lastSyncVersion != syncVersion) {
      _lastSyncVersion = syncVersion;
      // 同步完成后延迟刷新历史列表（非首次渲染）
      if (syncVersion > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadHistory();
        });
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('入库管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => const ManualBarcodeInput(),
              );
              if (result != null && result.isNotEmpty) {
                await _handleBarcode(result);
              }
            },
            tooltip: '手动输入条码',
          ),
          Row(children: [
            const Text('连续扫', style: TextStyle(fontSize: 12)),
            Switch(value: _batchMode, onChanged: (v) => setState(() => _batchMode = v)),
          ]),
        ],
      ),
      body: Column(
        children: [
          // 本次会话入库摘要
          if (_sessionItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本次已入库 ${_sessionItems.length} 种, ${_sessionItems.fold(0, (s, i) => s + i.quantity)} 件',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // 历史入库列表
          Expanded(
            child: _historyRecords.isEmpty
                ? _buildEmptyState()
                : _buildHistoryList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanBarcode,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(_batchMode ? '连续扫码' : '扫码入库'),
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        itemCount: _historyRecords.length,
        itemBuilder: (context, index) {
          final r = _historyRecords[index];
          final time = DateTime.parse(r['created_at'] as String);
          final timeStr = '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          final nameCn = r['name_cn'] as String? ?? '未知商品';
          final barcode = r['barcode'] as String? ?? '';
          final qty = (r['quantity'] as num?)?.toInt() ?? 0;
          final operatorName = r['operator_name'] as String? ?? '';
          // ★ 复合单位格式化
          final unitBig = r['unit_big'] as String?;
          final unitSmall = r['unit_small'] as String?;
          final unitRatio = (r['unit_ratio'] as num?)?.toInt() ?? 0;
          final qtyDisplay = (unitBig != null && unitSmall != null && unitRatio > 0)
              ? Product.formatCompositeQtyStatic(qty, unitBig, unitSmall, unitRatio)
              : '+$qty';
          // ★ v6.31: 判断临期/过期
          final expiryStr = r['expiry_date'] as String?;
          String? expiryLabel;
          Color? expiryColor;
          if (expiryStr != null && expiryStr.isNotEmpty) {
            final expiryDate = DateTime.tryParse(expiryStr);
            if (expiryDate != null) {
              final now = DateTime.now();
              final daysLeft = expiryDate.difference(now).inDays;
              if (daysLeft < 0) {
                expiryLabel = '已过期';
                expiryColor = Colors.red;
              } else if (daysLeft <= 30) {
                expiryLabel = '临期';
                expiryColor = Colors.orange;
              }
            }
          }
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: expiryColor ?? Colors.green.shade100,
              child: Icon(
                expiryLabel != null ? Icons.warning_amber_rounded : Icons.download,
                color: expiryLabel != null ? Colors.white : Colors.green,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(nameCn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                if (expiryLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: expiryColor!.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(expiryLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: expiryColor)),
                  ),
              ],
            ),
            subtitle: Text('$barcode · $operatorName · $timeStr'),
            trailing: Text(qtyDisplay, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
            onTap: () => _showInboundDetail(r),
          );
        },
      ),
    );
  }

  /// ★ v6.7 入库详情弹窗：条码、名称、时间、谁入库、数量、操作前库存、现在库存
  Future<void> _showInboundDetail(Map<String, dynamic> r) async {
    final qty = (r['quantity'] as num?)?.toInt() ?? 0;
    final nameCn = r['name_cn'] as String? ?? '未知商品';
    final barcode = r['barcode'] as String? ?? '';
    final timeStr = r['created_at'] as String? ?? '';
    final operatorName = r['operator_name'] as String? ?? '';
    final productId = r['product_id'] as int?;
    final recordId = r['id'] as int?;
    final priceCny = (r['price_cny'] as num?)?.toDouble() ?? 0;
    final priceUzs = (r['price_uzs'] as num?)?.toDouble() ?? 0;
    final note = r['note'] as String?;
    final supplier = r['supplier'] as String?;
    final expiryDateStr = r['expiry_date'] as String?;

    // ★ 判断临期/过期
    String? expiryLabel;
    Color? expiryColor;
    if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
      final expiryDate = DateTime.tryParse(expiryDateStr);
      if (expiryDate != null) {
        final daysLeft = expiryDate.difference(DateTime.now()).inDays;
        if (daysLeft < 0) {
          expiryLabel = '已过期 ($daysLeft天)';
          expiryColor = Colors.red;
        } else if (daysLeft <= 30) {
          expiryLabel = '临期 (剩余$daysLeft天)';
          expiryColor = Colors.orange;
        }
      }
    }

    // 查当前库存
    int currentStock = 0;
    if (productId != null) {
      final inv = await DatabaseService.instance.getInventoryByProductId(productId);
      currentStock = inv?.currentQuantity ?? 0;
    }
    // ★ v6.14: 操作前库存 = 现在库存 - 入库数量（锚定当前库存反算）
    int stockBefore = (currentStock - qty).clamp(0, 999999);

    if (!mounted) return;
    final currencySymbol = context.read<AppProvider>().countryConfig.currencySymbol;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(backgroundColor: Colors.green.shade100, child: const Icon(Icons.download, color: Colors.green, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Text(nameCn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ]),
              const Divider(height: 24),
              _detailRow('条码', barcode),
              _detailRow('入库时间', timeStr),
              _detailRow('操作人', operatorName),
              _detailRow('入库数量', '+$qty'),
              _detailRow('入库单价', '¥${priceCny.toStringAsFixed(2)}  /  ${priceUzs.toStringAsFixed(0)} $currencySymbol'),
              const Divider(height: 16),
              _detailRow('操作前库存', '$stockBefore', color: Colors.blue),
              _detailRow('现在库存', '$currentStock', color: Colors.green),
              if (expiryDateStr != null && expiryDateStr.isNotEmpty)
                _detailRow('保质期至', expiryDateStr, color: expiryColor ?? Colors.black87),
              if (expiryLabel != null)
                _detailRow('状态', expiryLabel, color: expiryColor),
              if (supplier != null && supplier.isNotEmpty)
                _detailRow('供应商', supplier),
              if (note != null && note.isNotEmpty)
                _detailRow('备注', note),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('点击右下角扫码入库', style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final result = await showDialog<String>(context: context, builder: (_) => ManualBarcodeInput(onSubmit: (s) {}));
              if (result != null) await _handleBarcode(result);
            },
            icon: const Icon(Icons.keyboard),
            label: const Text('手动输入条码'),
          ),
        ],
      ),
    );
  }
}

/// ★ v6.31: 复合单位选择器（预设 + 自定义）
class _UnitPresetPicker extends StatefulWidget {
  const _UnitPresetPicker();

  @override
  State<_UnitPresetPicker> createState() => _UnitPresetPickerState();
}

class _UnitPresetPickerState extends State<_UnitPresetPicker> {
  final _bigCtrl = TextEditingController(text: '箱');
  final _smallCtrl = TextEditingController(text: '罐');
  final _ratioCtrl = TextEditingController(text: '24');
  bool _custom = false;

  @override
  void dispose() {
    _bigCtrl.dispose();
    _smallCtrl.dispose();
    _ratioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择单位组合'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _StockInScreenState.unitPresets.map((p) => GestureDetector(
                onTap: () => Navigator.pop(context, p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: Text('1${p['big']}=${p['ratio']}${p['small']}', style: const TextStyle(fontSize: 13)),
                ),
              )).toList(),
            ),
            const Divider(height: 24),
            if (!_custom)
              OutlinedButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('自定义单位'),
                onPressed: () => setState(() => _custom = true),
              ),
            if (_custom) ...[
              TextField(controller: _bigCtrl, decoration: const InputDecoration(labelText: '大单位', hintText: '箱', isDense: true)),
              TextField(controller: _smallCtrl, decoration: const InputDecoration(labelText: '小单位', hintText: '罐', isDense: true)),
              TextField(controller: _ratioCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '比率', hintText: '一箱多少罐', isDense: true)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  final r = int.tryParse(_ratioCtrl.text) ?? 0;
                  if (_bigCtrl.text.isEmpty || _smallCtrl.text.isEmpty || r <= 0) return;
                  Navigator.pop(context, {'big': _bigCtrl.text, 'small': _smallCtrl.text, 'ratio': r});
                },
                child: const Text('确认'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}

class _StockInItem {
  final Product product;
  final int quantity;
  final DateTime? expiryDate;
  _StockInItem({required this.product, required this.quantity, this.expiryDate});
}
