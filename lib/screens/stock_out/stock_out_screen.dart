import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/product.dart';
import '../../models/stock_record.dart';
import '../../models/order.dart';
import '../../services/database_service.dart';
import '../../config/country_config.dart';
import '../../utils/product_detail_dialog.dart';
import '../../widgets/common/barcode_scanner.dart';

/// ★ v6.33: 出库管理（改造为按客户订单分组）
class StockOutScreen extends StatefulWidget {
  const StockOutScreen({super.key});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  bool _isHandlingBarcode = false;
  MobileScannerController? _scannerController;
  bool _batchMode = true;
  int _lastSyncVersion = 0;

  // ====== v6.33 订单相关状态 ======
  final _customerController = TextEditingController();
  int? _currentOrderId;                   // 当前正在创建的订单ID
  String? _currentCustomerName;           // 当前客户名
  final List<Map<String, dynamic>> _currentOrderItems = []; // {product, quantity, priceCny, priceUzs}
  bool _isOrderActive = false;            // 是否有进行中的订单

  // 订单历史列表
  List<Map<String, dynamic>> _ordersWithItems = [];

  @override
  void initState() {
    super.initState();
    _loadOrdersWithItems();
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  /// 加载订单历史
  Future<void> _loadOrdersWithItems() async {
    try {
      final orders = await DatabaseService.instance.getOrdersWithItems(limit: 100);
      if (mounted) {
        setState(() => _ordersWithItems = orders);
      }
    } catch (_) {}
  }

  /// 开始新订单
  void _startNewOrder() {
    final name = _customerController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入客户名'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _currentCustomerName = name;
      _currentOrderItems.clear();
      _currentOrderId = null;
      _isOrderActive = true;
    });
  }

  /// 完成当前订单
  Future<void> _completeOrder() async {
    if (_currentOrderItems.isEmpty) return;
    final appProvider = context.read<AppProvider>();
    final db = DatabaseService.instance;

    // 创建订单头
    final order = Order(
      customerName: _currentCustomerName!,
      operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
    );
    final orderId = await db.insertOrder(order);

    // 逐项保存出库记录
    final inventoryProvider = context.read<InventoryProvider>();
    for (final item in _currentOrderItems) {
      final product = item['product'] as Product;
      final qty = item['quantity'] as int;
      final note = item['note'] as String?;

      final record = StockRecord(
        productId: product.id!,
        barcode: product.barcode,
        type: StockType.outBound,
        quantity: qty,
        priceCny: product.priceCny,
        priceUzs: product.priceUzs,
        outboundReason: OutboundReason.sale,
        operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
        note: note,
        orderId: orderId,
      );
      await inventoryProvider.recordStockOut(record);
    }

    // 更新订单总额
    await db.updateOrderTotals(orderId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 出库订单已完成'), backgroundColor: Colors.green),
      );
    }

    setState(() {
      _isOrderActive = false;
      _currentOrderItems.clear();
      _currentOrderId = null;
      _currentCustomerName = null;
      _customerController.clear();
    });
    _loadOrdersWithItems();
  }

  /// 扫码处理
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

  /// 数量确认弹窗（改造：未开始订单则先提示）
  Future<void> _showQuantityDialog(Product product, int currentStock) async {
    // 检查是否已开始订单
    if (!_isOrderActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在顶部输入客户名并"开始订单"'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final hasComposite = product.unitBig != null && product.unitSmall != null && product.unitRatio != null && product.unitRatio! > 0;
    final countryConfig = context.read<AppProvider>().countryConfig;
    final currencySymbol = countryConfig.currencySymbol;
    final exchangeRate = countryConfig.cnyExchangeRate;

    final bigQtyController = TextEditingController(text: '0');
    final smallQtyController = TextEditingController(text: '0');
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        bool _useComposite = false;
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
            final totalLocal = product.priceCny * exchangeRate * qty;

            return AlertDialog(
              title: Text('${product.nameCn} → ${_currentCustomerName}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('条码: ${product.barcode}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('添加: $qtyDisplay', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('合计', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            Text('¥${totalCny.toStringAsFixed(2)}  /  ${totalLocal.toStringAsFixed(0)} $currencySymbol', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
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
                  onPressed: () {
                    if (qty <= 0) return;
                    if (qty > currentStock) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('数量($qtyDisplay)超过当前库存'), backgroundColor: Colors.red));
                      return;
                    }
                    setState(() {
                      _currentOrderItems.add({
                        'product': product,
                        'quantity': qty,
                        'note': noteController.text.isNotEmpty ? noteController.text : null,
                        'priceCny': product.priceCny,
                        'priceUzs': product.priceUzs,
                      });
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加: ${product.nameCn} x$qtyDisplay'), backgroundColor: Colors.green));
                  },
                  child: const Text('加入订单'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncVersion = context.watch<InventoryProvider>().syncVersion;
    if (_lastSyncVersion != syncVersion) {
      _lastSyncVersion = syncVersion;
      if (syncVersion > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadOrdersWithItems();
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
          // ========== v6.33: 客户订单面板 ==========
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.green.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customerController,
                        enabled: !_isOrderActive,
                        decoration: const InputDecoration(
                          labelText: '客户名',
                          prefixIcon: Icon(Icons.person),
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_isOrderActive)
                      ElevatedButton.icon(
                        onPressed: _startNewOrder,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('开始订单'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      )
                    else ...[
                      ElevatedButton.icon(
                        onPressed: _currentOrderItems.isEmpty ? null : _completeOrder,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('完成出库'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.grey),
                        onPressed: () => setState(() {
                          _isOrderActive = false;
                          _currentOrderItems.clear();
                          _customerController.clear();
                        }),
                        tooltip: '取消订单',
                      ),
                    ],
                  ],
                ),
                // 当前订单摘要
                if (_isOrderActive) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(_currentCustomerName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        Text('${_currentOrderItems.length} 种商品', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        if (_currentOrderItems.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text('¥${_currentOrderItems.fold(0.0, (s, i) => s + ((i['product'] as Product).priceCny * (i['quantity'] as int))).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                  // 当前订单商品清单
                  if (_currentOrderItems.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _currentOrderItems.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final item = _currentOrderItems[i];
                          final p = item['product'] as Product;
                          final qty = item['quantity'] as int;
                          return Chip(
                            avatar: CircleAvatar(child: Text('${i + 1}', style: const TextStyle(fontSize: 10))),
                            label: Text('${p.nameCn} x$qty', style: const TextStyle(fontSize: 12)),
                            onDeleted: () => setState(() => _currentOrderItems.removeAt(i)),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ========== 订单历史列表 ==========
          Expanded(
            child: _ordersWithItems.isEmpty
                ? _buildEmptyState()
                : _buildOrdersList(),
          ),
        ],
      ),
      floatingActionButton: _isOrderActive
          ? FloatingActionButton.extended(
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_batchMode ? '连续扫码' : '扫码出库'),
            )
          : null,
    );
  }

  /// 按订单分组的历史列表
  Widget _buildOrdersList() {
    return RefreshIndicator(
      onRefresh: _loadOrdersWithItems,
      child: ListView.builder(
        itemCount: _ordersWithItems.length,
        itemBuilder: (context, index) {
          final item = _ordersWithItems[index];
          final order = item['order'] as Order;
          final items = item['items'] as List<StockRecord>;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange.shade100,
                child: const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
              ),
              title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${order.createdAt.month}/${order.createdAt.day} ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}  ·  ${items.length}种  ·  ¥${order.totalAmountCny.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
              children: items.map((r) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.circle, size: 6, color: Colors.grey),
                  title: Text('${r.barcode}  x${r.quantity}', style: const TextStyle(fontSize: 13)),
                  trailing: Text('¥${r.totalCny.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无出库记录', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
