import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/product.dart';
import '../../models/stock_record.dart';
import '../../services/database_service.dart';
import '../../config/country_config.dart';
import '../../utils/product_detail_dialog.dart';
import '../../widgets/common/barcode_scanner.dart';

/// ==========================================================
/// 出库管理界面
/// 功能：
///   1. 扫码后立即写入DB（不再批量暂存）
///   2. _isHandlingBarcode 防止重复弹窗
///   3. 显示出库历史记录（从DB加载）
///   4. 支持选择出库原因
///   5. 支持复合单位（箱+瓶模式）
///   6. 显示单价(CNY/UZS)和数量×单价=总价
/// ==========================================================
class StockOutScreen extends StatefulWidget {
  const StockOutScreen({super.key});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  /// ★ 防止重复弹窗的标志位
  bool _isHandlingBarcode = false;

  /// 扫码控制器（用于外部暂停/恢复）
  MobileScannerController? _scannerController;

  /// 本次会话已完成的出库记录（用于顶部摘要显示）
  final List<_StockOutItem> _sessionItems = [];

  /// 历史出库记录（从DB加载）
  List<Map<String, dynamic>> _historyRecords = [];

  /// 当前选中的出库原因
  OutboundReason _selectedReason = OutboundReason.sale;

  /// 是否连续扫码模式
  bool _batchMode = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// 加载出库历史记录
  Future<void> _loadHistory() async {
    try {
      final records = await DatabaseService.instance.getStockRecordsWithName(type: StockType.outBound);
      if (mounted) {
        setState(() {
          _historyRecords = records;
        });
      }
    } catch (_) {}
  }

  /// 打开扫码界面
  Future<void> _scanBarcode() async {
    _scannerController = MobileScannerController();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: '扫码出库',
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

  /// ★ 处理扫码结果 — 防重复 + 弹窗确认 + 立即写入DB
  Future<void> _handleBarcode(String barcode) async {
    if (_isHandlingBarcode) return;
    _isHandlingBarcode = true;
    _scannerController?.stop();

    try {
      final provider = context.read<InventoryProvider>();
      final product = await provider.findProductByBarcode(barcode);

      if (product != null) {
        final inv = await DatabaseService.instance.getInventoryByProductId(product.id!);
        final currentStock = inv?.currentQuantity ?? 0;

        if (currentStock <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${product.nameCn} 库存为0，无法出库')),
            );
          }
          return;
        }

        await _showQuantityDialog(product, currentStock);
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('条码 $barcode 未找到商品'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      _isHandlingBarcode = false;
      if (mounted && _scannerController != null) {
        try { _scannerController!.start(); } catch (_) {}
      }
    }
  }

  /// 数量确认弹窗 — 支持复合单位 + 批次信息 + 原因选择
  Future<void> _showQuantityDialog(Product product, int currentStock) async {
    List<Map<String, dynamic>> productBatches = [];
    try {
      final nearExpiry = await DatabaseService.instance.getBatchNearExpiry();
      final expired = await DatabaseService.instance.getBatchExpired();
      for (final b in expired) {
        if ((b['product_id'] as int?) == product.id) productBatches.add({...b, '_status': 'expired'});
      }
      for (final b in nearExpiry) {
        if ((b['product_id'] as int?) == product.id) productBatches.add({...b, '_status': 'near_expiry'});
      }
    } catch (_) {}

    final hasComposite = product.unitBig != null && product.unitSmall != null && product.unitRatio != null && product.unitRatio! > 0;
    final countryConfig = context.read<AppProvider>().countryConfig;
    final currencySymbol = countryConfig.currencySymbol;
    final exchangeRate = countryConfig.cnyExchangeRate;

    final bigQtyController = TextEditingController(text: '0');
    final smallQtyController = TextEditingController(text: '0');
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();
    final _actualPriceController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        bool _useComposite = false; // ★ 默认普通单位
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int getTotalQty() {
              if (_useComposite) {
                final big = int.tryParse(bigQtyController.text) ?? 0;
                final small = int.tryParse(smallQtyController.text) ?? 0;
                return product.toTotalSmallQty(big, small);
              }
              return int.tryParse(qtyController.text) ?? 0;
            }

            final qty = getTotalQty();
            final qtyDisplay = _useComposite ? product.formatCompositeQtyDetail(qty) : '$qty${product.unit ?? "件"}';
            final totalCny = product.priceCny * qty;
            // ★ v6.32: 实时汇率计算当地售价，不依赖数据库 priceUzs
            final totalLocal = product.priceCny * exchangeRate * qty;

            return AlertDialog(
              title: Text(product.nameCn),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('条码: ${product.barcode}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    // 库存
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: currentStock <= 5 ? Colors.red.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '当前库存: ${hasComposite ? product.formatCompositeQty(currentStock) : "$currentStock"}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: currentStock <= 5 ? Colors.red : Colors.green),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 批次信息（临期/过期优先）
                    if (productBatches.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.warning_amber, size: 16, color: Colors.orange), SizedBox(width: 4), Text('系统将优先出掉临期/过期批次', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange))]),
                            const SizedBox(height: 6),
                            ...productBatches.map((b) {
                              final expiryStr = b['expiry_date'] as String? ?? '';
                              final batchQty = (b['total_qty'] as num?)?.toInt() ?? 0;
                              final isExpired = b['_status'] == 'expired';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(children: [
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: isExpired ? Colors.red : Colors.orange, borderRadius: BorderRadius.circular(3)), child: Text(isExpired ? '已过期' : '临期', style: const TextStyle(color: Colors.white, fontSize: 10))),
                                  const SizedBox(width: 6), Text('到期: $expiryStr', style: const TextStyle(fontSize: 12)),
                                  const Spacer(), Text('$batchQty件', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 出库原因
                    DropdownButtonFormField<OutboundReason>(
                      value: _selectedReason,
                      decoration: const InputDecoration(labelText: '出库原因', isDense: true),
                      items: OutboundReason.values.map((r) => DropdownMenuItem(value: r, child: Text(r.displayName))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _selectedReason = v); },
                    ),
                    const SizedBox(height: 12),

                    // ★ 数量输入 — 默认普通单位
                    if (_useComposite) ...[
                      Row(
                        children: [
                          Expanded(child: TextField(controller: bigQtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${product.unitBig}数', prefixIcon: const Icon(Icons.inventory_2), helperText: '1${product.unitBig}=${product.unitRatio}${product.unitSmall}'), onChanged: (_) => setDialogState(() {}))),
                          const SizedBox(width: 8),
                          Text('+', style: TextStyle(fontSize: 20, color: Colors.grey.shade400)),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: smallQtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${product.unitSmall}数', prefixIcon: const Icon(Icons.format_list_numbered)), onChanged: (_) => setDialogState(() {}))),
                        ],
                      ),
                      TextButton(onPressed: () => setDialogState(() => _useComposite = false), child: const Text('切回普通单位')),
                    ] else ...[
                      TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '出库数量（${product.unit ?? "件"}）', prefixIcon: const Icon(Icons.format_list_numbered)), autofocus: true, onChanged: (_) => setDialogState(() {})),
                      if (hasComposite)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.inventory_2, size: 16),
                          label: Text('使用复合单位 (1${product.unitBig}=${product.unitRatio}${product.unitSmall})'),
                          onPressed: () => setDialogState(() => _useComposite = true),
                        ),
                    ],

                    const SizedBox(height: 8),
                    // ★ 出库价格汇总
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('出库: $qtyDisplay', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('单价', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            Text('¥${product.priceCny.toStringAsFixed(2)}  /  ${(product.priceCny * exchangeRate).toStringAsFixed(0)} $currencySymbol', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ]),
                          const Divider(height: 16),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('原价合计', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            Text('¥${totalCny.toStringAsFixed(2)}  /  ${totalLocal.toStringAsFixed(0)} $currencySymbol', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ]),
                          const Divider(height: 16),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('实际售价', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            const Spacer(),
                            // ★ v6.32: 显示对应人民币价格
                            Text(
                              (() {
                                final inputLocal = double.tryParse(_actualPriceController.text) ?? totalLocal;
                                final inputCny = inputLocal / exchangeRate;
                                return '≈ ¥${inputCny.toStringAsFixed(2)}';
                              })(),
                              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 130,
                              child: TextField(
                                controller: _actualPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                                decoration: InputDecoration(
                                  hintText: totalLocal.toStringAsFixed(0),
                                  suffixText: ' $currencySymbol',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: noteController, decoration: const InputDecoration(labelText: '备注', prefixIcon: Icon(Icons.note))),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () async {
                    if (qty <= 0) return;
                    if (qty > currentStock) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('出库数量($qtyDisplay)超过当前库存'), backgroundColor: Colors.red));
                      return;
                    }
                    final appProvider = context.read<AppProvider>();
                    final inventoryProvider = context.read<InventoryProvider>();
                    final actualPriceStr = _actualPriceController.text.trim();
                    final actualTotal = actualPriceStr.isNotEmpty ? double.tryParse(actualPriceStr) : null;
                    final record = StockRecord(
                      productId: product.id!, barcode: product.barcode, type: StockType.outBound, quantity: qty,
                      priceCny: product.priceCny,
                      priceUzs: product.priceUzs,
                      outboundReason: _selectedReason,
                      operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
                      note: () {
                        final parts = <String>[];
                        if (noteController.text.isNotEmpty) parts.add(noteController.text);
                        if (actualTotal != null && actualTotal != totalLocal) parts.add('实际售价:${actualTotal.toStringAsFixed(0)}$currencySymbol');
                        return parts.isEmpty ? null : parts.join(' | ');
                      }(),
                    );
                    await inventoryProvider.recordStockOut(record);
                    setState(() => _sessionItems.add(_StockOutItem(product: product, quantity: qty, reason: _selectedReason)));
                    Navigator.pop(ctx);
                    _loadHistory();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已出库: ${product.nameCn} x$qtyDisplay'), backgroundColor: Colors.green));
                  },
                  child: const Text('确认出库'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  /// ★ v6.10: 监听同步版本号，同步完成后自动刷新历史列表
  int _lastSyncVersion = 0;

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
        title: const Text('出库管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => const ManualBarcodeInput(onSubmit: null),
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
          // ★ 本次会话出库摘要
          if (_sessionItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本次已出库 ${_sessionItems.length} 种, ${_sessionItems.fold(0, (s, i) => s + i.quantity)} 件',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ★ 历史出库列表
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
        label: Text(_batchMode ? '连续扫码' : '扫码出库'),
      ),
    );
  }

  /// 历史出库记录列表
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
          final reason = r['outbound_reason'] as String? ?? '';
          final reasonDisplay = _getReasonDisplay(reason);
          final operatorName = r['operator_name'] as String? ?? '';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: const Icon(Icons.upload, color: Colors.orange, size: 20),
            ),
            title: Text(nameCn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text('$barcode · $reasonDisplay · $operatorName · $timeStr'),
            trailing: Text('-$qty', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            onTap: () => _showOutboundDetail(r),
          );
        },
      ),
    );
  }

  /// ★ v6.7 出库详情弹窗
  Future<void> _showOutboundDetail(Map<String, dynamic> r) async {
    final qty = (r['quantity'] as num?)?.toInt() ?? 0;
    final nameCn = r['name_cn'] as String? ?? '未知商品';
    final barcode = r['barcode'] as String? ?? '';
    final timeStr = r['created_at'] as String? ?? '';
    final operatorName = r['operator_name'] as String? ?? '';
    final productId = r['product_id'] as int?;
    final priceCny = (r['price_cny'] as num?)?.toDouble() ?? 0;
    final priceUzs = (r['price_uzs'] as num?)?.toDouble() ?? 0;
    final reason = r['outbound_reason'] as String? ?? '';
    final reasonDisplay = _getReasonDisplay(reason);
    final note = r['note'] as String?;
    final destination = r['destination'] as String?;
    // ★ 复合单位
    final unitBig = r['unit_big'] as String?;
    final unitSmall = r['unit_small'] as String?;
    final unitRatio = (r['unit_ratio'] as num?)?.toInt() ?? 0;
    final qtyDisplay = (unitBig != null && unitSmall != null && unitRatio > 0)
        ? Product.formatCompositeQtyStatic(qty, unitBig, unitSmall, unitRatio)
        : '-$qty';

    int currentStock = 0;
    if (productId != null) {
      final inv = await DatabaseService.instance.getInventoryByProductId(productId);
      currentStock = inv?.currentQuantity ?? 0;
    }
    int stockBefore = currentStock + qty;

    // ★ v6.31: 解析实际售价 + 清洗备注
    final cleanNote = note != null ? note.replaceAll(RegExp(r'\s*实际售价:\d+(?:\.\d+)?\D*\s*'), '').trim() : null;
    final originalTotal = priceUzs * qty;
    double? actualPrice;
    if (note != null) {
      final match = RegExp(r'实际售价:(\d+(?:\.\d+)?)').firstMatch(note);
      if (match != null) {
        actualPrice = double.tryParse(match.group(1)!);
      }
    }
    final actualTotal = actualPrice ?? originalTotal;

    // ★ v6.32: 获取当前汇率，用于双币显示
    final countryConfig = context.read<AppProvider>().countryConfig;
    final currencySymbol = countryConfig.currencySymbol;
    final exchangeRate = countryConfig.cnyExchangeRate;
    final localPrice = (priceCny * exchangeRate).toStringAsFixed(0);
    final localTotal = (priceCny * exchangeRate * qty).toStringAsFixed(0);
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
                CircleAvatar(backgroundColor: Colors.orange.shade100, child: const Icon(Icons.upload, color: Colors.orange, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Text(nameCn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ]),
              const Divider(height: 24),
              _detailRow('条码', barcode),
              _detailRow('出库时间', timeStr),
              _detailRow('操作人', operatorName),
              _detailRow('出库原因', reasonDisplay),
              _detailRow('出库数量', qtyDisplay, color: Colors.red),
              _detailRow('标价单价', '¥${priceCny.toStringAsFixed(2)}  /  $localPrice $currencySymbol'),
              // ★ v6.31: 显示实际出库金额
              if (actualPrice != null) ...[
                _detailRow('标价金额', '¥${(priceCny * qty).toStringAsFixed(2)}  /  $localTotal $currencySymbol', color: Colors.grey),
                _detailRow('实际售价', '${actualTotal.toStringAsFixed(0)} $currencySymbol  /  ≈ ¥${(actualTotal / exchangeRate).toStringAsFixed(2)}', color: Colors.red),
              ] else
                _detailRow('出库金额', '¥${(priceCny * qty).toStringAsFixed(2)}  /  $localTotal $currencySymbol', color: Colors.red),
              const Divider(height: 16),
              _detailRow('操作前库存', '$stockBefore', color: Colors.blue),
              _detailRow('现在库存', '$currentStock', color: Colors.green),
              if (destination != null && destination.isNotEmpty)
                _detailRow('目的地', destination),
              if (cleanNote != null && cleanNote.isNotEmpty)
                _detailRow('备注', cleanNote),
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

  /// 出库原因映射到中文显示名
  String _getReasonDisplay(String reason) {
    switch (reason) {
      case 'sale': return '销售出库';
      case 'loss': return '损耗出库';
      case 'damage': return '破损出库';
      case 'expiry': return '过期出库';
      case 'returnToSupplier': return '退货出库';
      case 'other': return '其他';
      default: return reason;
    }
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('点击右下角扫码出库', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

/// 本次会话出库条目（仅用于顶部摘要显示）
class _StockOutItem {
  final Product product;
  final int quantity;
  final OutboundReason reason;

  _StockOutItem({
    required this.product,
    required this.quantity,
    required this.reason,
  });
}
