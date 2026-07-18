import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/check_task.dart';
import '../../models/product.dart';
import '../../models/inventory.dart';
import '../../services/database_service.dart';
import '../../widgets/common/barcode_scanner.dart';

import '../../config/constants.dart';

class CheckDetailScreen extends StatefulWidget {
  final CheckTask task;

  const CheckDetailScreen({super.key, required this.task});

  @override
  State<CheckDetailScreen> createState() => _CheckDetailScreenState();
}

class _CheckDetailScreenState extends State<CheckDetailScreen> {
  final List<_CheckItem> _checkItems = [];
  MobileScannerController? _scannerController;
  /// ★ v6.27: 未盘点商品列表（该任务对应货架上库存>0但尚未扫描的商品）
  List<Map<String, dynamic>> _unpickedProducts = [];
  bool _showUnpicked = false;
  /// ★ v6.29: 之前已保存到数据库的盘点明细条码（跨会话不丢失）
  final Set<String> _previouslyScannedBarcodes = {};

  @override
  void initState() {
    super.initState();
    _loadInventoryForCheck();
  }

  Future<void> _loadInventoryForCheck() async {
    await context.read<InventoryProvider>().loadInventory();
    // ★ v6.29: 加载该任务已有的盘点明细条码，避免重开会话后未盘点数不准确
    await _loadExistingCheckDetails();
    _computeUnpickedProducts();
  }

  /// ★ v6.29: 加载该任务已保存到数据库的盘点明细条码
  Future<void> _loadExistingCheckDetails() async {
    try {
      if (widget.task.id == null) return;
      final db = DatabaseService.instance;
      final existingDetails = await db.getCheckDetailsByTaskId(widget.task.id!);
      _previouslyScannedBarcodes.addAll(existingDetails.map((d) => d.barcode));
      debugPrint('[CheckDetail] loaded ${_previouslyScannedBarcodes.length} previously scanned barcodes');
    } catch (_) {
      _previouslyScannedBarcodes.clear();
    }
  }

  /// ★ v6.27: 计算该任务尚未盘点的商品（该货架库存>0 但未扫描的商品）
  Future<void> _computeUnpickedProducts() async {
    try {
      final db = DatabaseService.instance;
      // ★ v6.29: 合并当前会话扫描的条码 + 之前已保存到数据库的条码
      final sessionBarcodes = _checkItems.map((i) => i.product.barcode).toSet();
      final allScannedBarcodes = {...sessionBarcodes, ..._previouslyScannedBarcodes};
      final allUnchecked = await db.getUncheckedProducts(allScannedBarcodes.toList());
      // 如果有 shelfFilter，只显示该货架的商品
      final shelfFilter = widget.task.shelfFilter;
      if (shelfFilter != null && shelfFilter.isNotEmpty) {
        final shelfCodes = shelfFilter.split(',').map((s) => s.trim()).toSet();
        _unpickedProducts = allUnchecked.where((p) {
          final loc = p['shelf_location'] as String? ?? '';
          return shelfCodes.any((sc) => loc.contains(sc));
        }).toList();
      } else {
        _unpickedProducts = allUnchecked;
      }
      if (mounted) setState(() {});
    } catch (_) {
      _unpickedProducts = [];
    }
  }

  Future<void> _startScanning() async {
    _isHandlingBarcode = false;
    _scannerController = MobileScannerController();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerWidget(
          title: '扫码盘点: ${widget.task.title}',
          continuous: true,
          externalController: _scannerController,
          onScan: (barcode, format) async {
            await _processBarcode(barcode);
          },
        ),
      ),
    );
    _scannerController?.dispose();
    _scannerController = null;
  }

  bool _isHandlingBarcode = false;

  Future<void> _processBarcode(String barcode) async {
    if (_isHandlingBarcode) return;
    _isHandlingBarcode = true;
    _scannerController?.stop();

    try {
      final provider = context.read<InventoryProvider>();
      final product = await provider.findProductByBarcode(barcode);

      if (product == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('未找到商品: $barcode')),
          );
        }
        return;
      }

      if (product.priceCny == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('预置商品: ${product.nameCn}，建议补充价格信息')),
        );
      }

      final allInventory = provider.inventoryList;
      final invMap = allInventory.firstWhere(
        (i) => i['barcode'] == barcode,
        orElse: () => {},
      );
      final systemQty = invMap.isNotEmpty ? (invMap['current_quantity'] as int? ?? 0) : 0;

      int expiredQty = 0;
      int nearExpiryQty = 0;
      try {
        final expired = await DatabaseService.instance.getBatchExpired();
        for (final b in expired) {
          if ((b['barcode'] as String?) == barcode) {
            expiredQty = (b['total_qty'] as num?)?.toInt() ?? 0;
            break;
          }
        }
      } catch (_) {}
      try {
        final nearExpiry = await DatabaseService.instance.getBatchNearExpiry();
        for (final b in nearExpiry) {
          if ((b['barcode'] as String?) == barcode) {
            nearExpiryQty = (b['total_qty'] as num?)?.toInt() ?? 0;
            break;
          }
        }
      } catch (_) {}

      String? shelfLocation;
      if (invMap.isNotEmpty) {
        final invShelfLoc = invMap['shelf_location'] as String?;
        if (invShelfLoc != null && invShelfLoc.isNotEmpty) {
          shelfLocation = invShelfLoc;
        }
      }
      shelfLocation ??= product.shelfLocation;

      await _showCheckQuantityDialog(product, systemQty, expiredQty, nearExpiryQty, shelfLocation);
    } finally {
      _isHandlingBarcode = false;
      if (mounted && _scannerController != null) {
        try { _scannerController!.start(); } catch (_) {}
      }
    }
  }

  Future<void> _showCheckQuantityDialog(Product product, int systemQty, int expiredQty, int nearExpiryQty, String? shelfLocation) async {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    final actualExpiredController = TextEditingController();
    final actualNearExpiryController = TextEditingController();
    final shelfLocationController = TextEditingController(text: shelfLocation ?? '');

    // ★ v6.27: 货架位置预设选项改为从数据库动态读取
    final provider = context.read<InventoryProvider>();
    final shelfCodes = provider.shelves.map((s) => s.code).toList();
    final shelfPresets = shelfCodes.isNotEmpty ? shelfCodes : <String>[];
    String _selectedShelf = shelfLocation ?? '';
    bool _customShelfMode = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(product.nameCn),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 条码
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(product.barcode, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 多语言名称
              if (product.nameRu != null && product.nameRu!.isNotEmpty)
                _buildInfoRow('俄语:', product.nameRu!),
              if (product.nameUz != null && product.nameUz!.isNotEmpty)
                _buildInfoRow('乌兹别克语:', product.nameUz!),

              // 品类
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(product.category, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                    backgroundColor: Colors.grey.shade200,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const Divider(height: 20),

              // ★ 货架位置（下拉选择 + 自定义）
              if (!_customShelfMode) ...[
                DropdownButtonFormField<String>(
                  value: shelfPresets.contains(_selectedShelf) ? _selectedShelf : (_selectedShelf.isNotEmpty ? null : null),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '货架位置',
                    prefixIcon: const Icon(Icons.shelves, size: 18, color: Colors.indigo),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    ...shelfPresets.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, style: const TextStyle(fontSize: 13)),
                    )),
                    DropdownMenuItem(
                      value: '__custom__',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 14, color: Colors.blue),
                          const SizedBox(width: 6),
                          Text('自定义输入...', style: TextStyle(fontSize: 13, color: Colors.blue.shade700)),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == '__custom__') {
                      setDialogState(() { _customShelfMode = true; });
                    } else if (value != null) {
                      setDialogState(() {
                        _selectedShelf = value;
                        shelfLocationController.text = value;
                      });
                    }
                  },
                ),
              ] else ...[
                // 自定义货架位置输入
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: shelfLocationController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: '自定义货架位置',
                          prefixIcon: const Icon(Icons.shelves, size: 18, color: Colors.indigo),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (v) => setDialogState(() { _selectedShelf = v; }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: () => setDialogState(() { _customShelfMode = false; }),
                      tooltip: '返回选择',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              // 保质期
              if (product.expiryDate != null)
                _buildInfoRow('保质期至:', '${product.expiryDate!.year}-${product.expiryDate!.month.toString().padLeft(2, '0')}-${product.expiryDate!.day.toString().padLeft(2, '0')}'),

              // 系统数量（高亮）
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('系统数量', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                    Text('$systemQty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ★ 过期数量和临期数量（可编辑，系统以此为最终数据）
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                              child: const Text('已过期', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 4),
                            Text('系统: $expiredQty', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: actualExpiredController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '$expiredQty',
                            prefixIcon: const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            filled: true,
                            fillColor: Colors.red.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                              child: const Text('临期商品', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 4),
                            Text('系统: $nearExpiryQty', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: actualNearExpiryController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '$nearExpiryQty',
                            prefixIcon: const Icon(Icons.access_time, color: Colors.orange, size: 18),
                            filled: true,
                            fillColor: Colors.orange.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 实际数量输入
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '实际数量 *',
                  hintText: '请输入实际盘点数量',
                  prefixIcon: const Icon(Icons.edit),
                  filled: true,
                  fillColor: Colors.amber.shade50,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.amber, width: 2),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final actualQty = int.tryParse(qtyController.text) ?? -1;
              if (actualQty < 0) return;

              setState(() {
                final existingIndex = _checkItems.indexWhere((i) => i.product.id == product.id);
                if (existingIndex >= 0) {
                  _checkItems[existingIndex] = _CheckItem(
                    product: product,
                    systemQuantity: systemQty,
                    actualQuantity: actualQty,
                    actualExpiredQty: actualExpiredController.text.isNotEmpty ? int.tryParse(actualExpiredController.text) : null,
                    actualNearExpiryQty: actualNearExpiryController.text.isNotEmpty ? int.tryParse(actualNearExpiryController.text) : null,
                    shelfLocation: shelfLocation,
                    editedShelfLocation: shelfLocationController.text.isNotEmpty ? shelfLocationController.text : null,
                    note: noteController.text,
                  );
                } else {
                  _checkItems.add(_CheckItem(
                    product: product,
                    systemQuantity: systemQty,
                    actualQuantity: actualQty,
                    actualExpiredQty: actualExpiredController.text.isNotEmpty ? int.tryParse(actualExpiredController.text) : null,
                    actualNearExpiryQty: actualNearExpiryController.text.isNotEmpty ? int.tryParse(actualNearExpiryController.text) : null,
                    shelfLocation: shelfLocation,
                    editedShelfLocation: shelfLocationController.text.isNotEmpty ? shelfLocationController.text : null,
                    note: noteController.text,
                  ));
                }
              });

              Navigator.pop(context);
              _computeUnpickedProducts();  // ★ v6.27: 扫描后刷新未盘点列表
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已记录: ${product.nameCn} = $actualQty')),
              );
            },
            child: const Text('确认'),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCheck() async {
    if (_checkItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先盘点至少一个商品')),
      );
      return;
    }

    final db = DatabaseService.instance;
    final details = <CheckDetail>[];

    try {
      for (final item in _checkItems) {
        // Build extra info note with actual expired/near-expiry counts
        final extraParts = <String>[];
        if (item.actualExpiredQty != null) extraParts.add('实际过期:${item.actualExpiredQty}');
        if (item.actualNearExpiryQty != null) extraParts.add('实际临期:${item.actualNearExpiryQty}');
        if (item.editedShelfLocation != null && item.editedShelfLocation!.isNotEmpty) {
          extraParts.add('货架:${item.editedShelfLocation}');
        }
        final combinedNote = [
          if (item.note != null && item.note!.isNotEmpty) item.note,
          if (extraParts.isNotEmpty) extraParts.join(', '),
        ].where((s) => s != null && s.isNotEmpty).join(' | ');

        details.add(CheckDetail(
          taskId: widget.task.id!,
          productId: item.product.id!,
          barcode: item.product.barcode,
          systemQuantity: item.systemQuantity,
          actualQuantity: item.actualQuantity,
          difference: item.actualQuantity - item.systemQuantity,
          note: combinedNote.isNotEmpty ? combinedNote : null,
          actualExpiredQty: item.actualExpiredQty,
          actualNearExpiryQty: item.actualNearExpiryQty,
          shelfLocation: item.editedShelfLocation,
        ));

        // ★ 以用户输入的最终数据更新库存
        final diff = item.actualQuantity - item.systemQuantity;
        if (diff != 0) {
          await db.updateInventoryQuantity(item.product.id!, item.actualQuantity);
        }

        // ★ 更新货架位置（保留原有 minStockLevel）
        if (item.editedShelfLocation != null && item.editedShelfLocation!.isNotEmpty) {
          final inv = await db.getInventoryByProductId(item.product.id!);
          if (inv != null) {
            await db.upsertInventory(inv.copyWith(
              shelfLocation: item.editedShelfLocation,
            ));
          }
        }
      }

      await context.read<InventoryProvider>().submitCheckResult(widget.task.id!, details);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('盘点提交成功'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('盘点提交失败: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('盘点提交失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => const ManualBarcodeInput(),
              );
              if (result != null && result.isNotEmpty) {
                await _processBarcode(result);
              }
            },
            tooltip: '手动输入条码',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已盘点 ${_checkItems.length} 项${_unpickedProducts.isNotEmpty ? ' · 未盘点 ${_unpickedProducts.length} 项' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: _checkItems.isEmpty ? 0 : (_checkItems.length / (_checkItems.length + _unpickedProducts.length)).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey.shade200,
                        color: _unpickedProducts.isNotEmpty ? Colors.orange : AppConstants.primaryColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _submitCheck,
                  icon: const Icon(Icons.check),
                  label: const Text('提交'),
                ),
              ],
            ),
          ),
          // ★ v6.27: 未盘点提醒横幅
          if (_unpickedProducts.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _showUnpicked = !_showUnpicked),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('还有 ${_unpickedProducts.length} 种商品未盘点', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w500))),
                    Icon(_showUnpicked ? Icons.expand_less : Icons.expand_more, color: Colors.orange.shade700),
                  ],
                ),
              ),
            ),
            if (_showUnpicked)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                color: Colors.orange.shade50,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: _unpickedProducts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final p = _unpickedProducts[index];
                    return ListTile(
                      dense: true,
                      title: Text(p['name_cn'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${p['barcode']} · 库存: ${p['current_quantity']} · ${p['shelf_location'] ?? ''}', style: const TextStyle(fontSize: 11)),
                    );
                  },
                ),
              ),
          ],
          Expanded(
            child: _checkItems.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _checkItems.length,
                    itemBuilder: (context, index) {
                      final item = _checkItems[index];
                      final diff = item.actualQuantity - item.systemQuantity;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: diff == 0
                              ? Colors.green.shade100
                              : diff > 0
                                  ? Colors.blue.shade100
                                  : Colors.red.shade100,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(item.product.nameCn),
                        subtitle: Text(
                          '系统: ${item.systemQuantity} → 实际: ${item.actualQuantity}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: diff == 0
                                ? Colors.green.withOpacity(0.1)
                                : diff > 0
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            diff >= 0 ? '+$diff' : '$diff',
                            style: TextStyle(
                              color: diff == 0
                                  ? Colors.green
                                  : diff > 0
                                      ? Colors.blue
                                      : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScanning,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('扫码盘点'),
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
          Text('点击右下角开始扫码盘点', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _CheckItem {
  final Product product;
  final int systemQuantity;
  final int actualQuantity;
  final int? actualExpiredQty;
  final int? actualNearExpiryQty;
  final String? shelfLocation;
  final String? editedShelfLocation;
  final String? note;

  _CheckItem({
    required this.product,
    required this.systemQuantity,
    required this.actualQuantity,
    this.actualExpiredQty,
    this.actualNearExpiryQty,
    this.shelfLocation,
    this.editedShelfLocation,
    this.note,
  });
}
