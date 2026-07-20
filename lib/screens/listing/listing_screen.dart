import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../services/database_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../models/product.dart';
import '../../models/shelf.dart';
import '../../config/country_config.dart';

class ListingScreen extends StatefulWidget {
  const ListingScreen({super.key});

  @override
  State<ListingScreen> createState() => _ListingScreenState();
}

class _ListingScreenState extends State<ListingScreen> {
  final _db = DatabaseService.instance;
  late Future<List<Product>> _productsFuture;
  List<Shelf> _shelves = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadShelves();
  }

  Future<void> _loadShelves() async {
    final provider = context.read<InventoryProvider>();
    await provider.loadShelves();
    if (mounted) setState(() => _shelves = provider.shelves);
  }

  Future<void> _refresh() async {
    setState(() {
      _productsFuture = _db.getUnpricedProducts();
    });
  }

  /// 获取当地货币显示符号
  CountryConfig get _countryConfig => context.read<AppProvider>().countryConfig;

  /// 人民币 → 当地货币转换
  String _localToCny(double local) {
    final rate = _countryConfig.cnyExchangeRate;
    final cny = local / rate;
    if (rate >= 100) return '¥${cny.toStringAsFixed(2)}';
    return '¥${cny.toStringAsFixed(2)}';
  }

  /// ★ v6.32: 价格设置弹窗 — 进价+售价双币种 + 加权均价
  Future<void> _showPriceDialog(Product product) async {
    final costLocalController = TextEditingController(text: product.costPriceCny > 0 ? (product.costPriceCny * _countryConfig.cnyExchangeRate).toStringAsFixed(0) : '');
    final sellLocalController = TextEditingController(text: product.priceCny > 0 ? (product.priceCny * _countryConfig.cnyExchangeRate).toStringAsFixed(0) : '');
    final newQtyController = TextEditingController();
    final newCostLocalController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final symbol = _countryConfig.currencySymbol;

    // 获取当前库存
    int currentStock = 0;
    try {
      final inv = await DatabaseService.instance.getInventoryByProductId(product.id!);
      currentStock = inv?.currentQuantity ?? 0;
    } catch (_) {}

    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double costLocal = double.tryParse(costLocalController.text) ?? 0;
          double sellLocal = double.tryParse(sellLocalController.text) ?? 0;
          final newQty = int.tryParse(newQtyController.text) ?? 0;
          final newCostLocal = double.tryParse(newCostLocalController.text) ?? 0;
          final rate = _countryConfig.cnyExchangeRate;
          final costCny = rate > 0 ? costLocal / rate : 0;
          final sellCny = rate > 0 ? sellLocal / rate : 0;
          final newCostCny = rate > 0 ? newCostLocal / rate : 0;
          final weighted = (newQty > 0 && newCostCny > 0 && currentStock > 0)
              ? ((currentStock * costCny + newQty * newCostCny) / (currentStock + newQty))
              : 0.0;
          return AlertDialog(
            title: Text(product.nameCn),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前库存
                    Text('当前库存: $currentStock 件',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    const Divider(height: 20),
                    // 进价
                    const Text('进价（成本）', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: costLocalController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '进价 ($symbol 当地货币)',
                        prefixText: '$symbol ',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      validator: (v) {
                        if (v == null || v.isEmpty) return '请输入进价';
                        final n = double.tryParse(v);
                        if (n == null || n < 0) return '请输入有效价格';
                        return null;
                      },
                    ),
                    if (costLocal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('≈ ¥${costCny.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                    // 新进货加权区
                    if (currentStock > 0) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const Text('新进货加权均价', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: newQtyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '数量（件）', border: OutlineInputBorder()),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child:                           TextField(
                            controller: newCostLocalController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: '进价 ($symbol)', prefixText: '$symbol ', border: const OutlineInputBorder()),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                      ]),
                      if (weighted > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Row(children: [
                            const Text('加权均价: ', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('¥${weighted.toStringAsFixed(3)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                          ]),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    // 售价
                    const Text('售价', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: sellLocalController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '售价 ($symbol 当地货币)',
                        prefixText: '$symbol ',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      validator: (v) {
                        if (v == null || v.isEmpty) return '请输入售价';
                        final n = double.tryParse(v);
                        if (n == null || n < 0) return '请输入有效价格';
                        return null;
                      },
                    ),
                    if (sellLocal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('≈ ¥${sellCny.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (weighted > 0)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'weighted'),
                  child: const Text('按库存均摊'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, 'direct');
                  }
                },
                child: const Text('直接改价'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == 'cancel' || confirmed == null || !mounted) return;

    final costLocal = double.tryParse(costLocalController.text) ?? 0;
    final sellLocal = double.tryParse(sellLocalController.text) ?? 0;
    final rate = _countryConfig.cnyExchangeRate;
    final sellCny = rate > 0 ? sellLocal / rate : 0;
    final costCny = rate > 0 ? costLocal / rate : 0;
    final sellLocal = double.tryParse(sellLocalController.text) ?? 0;

    // 如果选了按库存均摊，使用加权均价
    double effectiveCost = costCny;
    if (confirmed == 'weighted') {
      final newQty = int.tryParse(newQtyController.text) ?? 0;
      final newCost = double.tryParse(newCostController.text) ?? 0;
      if (newQty > 0 && newCost > 0 && currentStock > 0) {
        effectiveCost = (currentStock * costCny + newQty * newCost) / (currentStock + newQty);
      }
    }

    final provider = context.read<InventoryProvider>();
    await provider.updateProductPrices(product.id!, sellCny, sellLocal, costPriceCny: effectiveCost);
    // 同步价格 + 分类到云端
    SupabaseSyncService().syncProductPrice(product.barcode, effectiveCost, sellLocal,
        sellPriceCny: sellCny, categoryName: product.category).catchError((_) {});
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.nameCn} 价格已设置: 进价¥${effectiveCost.toStringAsFixed(2)} / 售价¥$sellCny'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 货架位置设置弹窗
  Future<void> _showShelfDialog(Product product) async {
    final provider = context.read<InventoryProvider>();
    await provider.loadShelves();
    final shelves = provider.shelves;

    if (shelves.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无货架，请先在货架管理中创建货架')),
      );
      return;
    }

    String? selectedCode = product.shelfLocation;
    if (selectedCode != null && !shelves.any((s) => s.code == selectedCode)) {
      selectedCode = null;
    }

    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${product.nameCn} — 设置货架位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前: ${product.shelfLocation ?? "未设置"}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedCode,
                decoration: const InputDecoration(
                  labelText: '选择货架',
                  border: OutlineInputBorder(),
                ),
                items: shelves.map((s) {
                  return DropdownMenuItem(
                    value: s.code,
                    child: Text('${s.code} — ${s.name} (${s.zone})'),
                  );
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedCode = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: selectedCode == null ? null : () => Navigator.pop(ctx, selectedCode),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != null && mounted) {
      await _db.updateProductShelf(product.id!, confirmed);
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.nameCn} 已设置货架: $confirmed'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上架管理'),
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return _buildEmptyState();
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                final hasPrice = product.priceCny > 0;
                final hasShelf = product.shelfLocation != null && product.shelfLocation!.isNotEmpty;
                final isListed = hasPrice && hasShelf;  // ★ 已上架 = 有价格+有货架
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.nameCn,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            // ★ 上架状态标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: isListed ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isListed ? Colors.green.shade300 : Colors.orange.shade300),
                              ),
                              child: Text(
                                isListed ? '已上架' : '未上架',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isListed ? Colors.green.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            if (hasPrice) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Text('¥${product.priceCny.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('条码: ${product.barcode}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        if (product.category.isNotEmpty)
                          Text('分类: ${product.category}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        if (hasShelf)
                          Text('货架: ${product.shelfLocation}', style: TextStyle(fontSize: 13, color: Colors.indigo)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showPriceDialog(product),
                                icon: Icon(Icons.attach_money, size: 18, color: hasPrice ? Colors.green : null),
                                label: Text(hasPrice ? '修改价格' : '设置价格', style: const TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasPrice ? Colors.green.shade50 : null,
                                  foregroundColor: hasPrice ? Colors.green.shade800 : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showShelfDialog(product),
                                icon: Icon(Icons.shelves, size: 18, color: hasShelf ? Colors.indigo : null),
                                label: Text(hasShelf ? '修改货架' : '货架位置', style: const TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasShelf ? Colors.indigo.shade50 : null,
                                  foregroundColor: hasShelf ? Colors.indigo.shade800 : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
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
          Icon(Icons.inventory_2, size: 72, color: Colors.green.shade300),
          const SizedBox(height: 16),
          Text('暂无可上架商品', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('请先通过入库管理添加商品库存', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
