import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../config/constants.dart';
import '../../widgets/common/currency_display.dart';
import '../../models/product.dart';

/// 格式化复合单位数量
String _formatInvQty(Map<String, dynamic> item, int qty) {
  final unitBig = item['unit_big'] as String?;
  final unitSmall = item['unit_small'] as String?;
  final unitRatio = item['unit_ratio'] as int?;
  if (unitBig != null && unitSmall != null && unitRatio != null && unitRatio > 0) {
    final big = qty ~/ unitRatio;
    final small = qty % unitRatio;
    if (big > 0) {
      return small > 0 ? '$big$unitBig$small$unitSmall' : '$big$unitBig';
    }
    return '$small$unitSmall';
  }
  return '$qty';
}

class InventoryListTab extends StatefulWidget {
  const InventoryListTab({super.key});

  @override
  State<InventoryListTab> createState() => _InventoryListTabState();
}

class _InventoryListTabState extends State<InventoryListTab> {
  String _searchQuery = '';
  String? _selectedCategory;
  bool _showLowStockOnly = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: Consumer<InventoryProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = provider.inventoryList;

              if (items.isEmpty) {
                return const Center(child: Text('暂无库存数据'));
              }

              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return _buildInventoryCard(items[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: '搜索商品名称/条码...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                        _applyFilters();
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('全部'),
                        selected: _selectedCategory == null && !_showLowStockOnly,
                        onSelected: (_) => _clearFilters(),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('低库存', style: TextStyle(color: Colors.red)),
                        selected: _showLowStockOnly,
                        selectedColor: Colors.red.shade100,
                        onSelected: (selected) {
                          setState(() => _showLowStockOnly = selected);
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _showLowStockOnly = false;
    });
    _applyFilters();
  }

  void _applyFilters() {
    context.read<InventoryProvider>().loadInventory(
      category: _selectedCategory,
      lowStockOnly: _showLowStockOnly,
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final name = item['name_cn'] as String? ?? '';
    final nameRu = item['name_ru'] as String?;
    final nameUz = item['name_uz'] as String?;
    final category = item['category'] as String? ?? '';
    final qty = item['current_quantity'] as int? ?? 0;
    final minStock = item['min_stock_level'] as int? ?? 10;
    final priceCny = (item['price_cny'] as num?)?.toDouble() ?? 0;
    final priceUzs = (item['price_uzs'] as num?)?.toDouble() ?? 0;
    final shelf = item['shelf_location'] as String?;
    final isLow = qty <= minStock;
    final qtyDisplay = _formatInvQty(item, qty);

    return Card(
      child: ListTile(
        leading: Container(
          width: 58,
          height: 48,
          decoration: BoxDecoration(
            color: isLow ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              qtyDisplay,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isLow ? Colors.red : Colors.green,
              ),
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nameRu != null && nameRu.isNotEmpty)
              Text(nameRu, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (nameUz != null && nameUz.isNotEmpty)
              Text(nameUz, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Row(
              children: [
                Chip(
                  label: Text(category, style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (shelf != null && shelf.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.shelves, size: 14, color: Colors.grey.shade600),
                  Text(shelf, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ],
            ),
            CurrencyDisplay(
              amountCny: priceCny,
              amountUzs: priceUzs,
              compact: true,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: isLow
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '低库存',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              )
            : null,
      ),
    );
  }
}
