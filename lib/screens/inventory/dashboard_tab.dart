import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../config/constants.dart';
import '../../services/database_service.dart';
import '../../models/stock_record.dart';
import '../../widgets/common/currency_display.dart';
/// 通过 item map 中的 unit 字段格式化复合数量
String _formatQtyWithUnit(Map<String, dynamic> item, int qty) {
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

/// ==========================================================
/// 看板界面（Dashboard）
/// 功能：
///   1. 统计卡片：商品总数、库存总量、今日入库、今日出库
///   2. 预警卡片：低库存预警、临期商品、已过期
///   3. 所有列表项含 商品名、条码、数量
///   4. 点击列表项 → 商品详情弹窗（含批次信息）
///   5. 临期/过期/低库存 按批次级别显示
/// ==========================================================
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().loadStoreName(); // ★ v6.31: 刷新门店名称
      context.read<InventoryProvider>().loadDashboardStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();

    return Consumer<InventoryProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.dashboardStats.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final stats = provider.dashboardStats;
        return SafeArea(
          top: false,
          child: RefreshIndicator(
          onRefresh: () => provider.loadDashboardStats(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(appProvider.storeName),
                const SizedBox(height: 16),
                _buildStatsGrid(stats),
                const SizedBox(height: 20),
                _buildAlertsSection(stats),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  // ==================== HEADER ====================

  Widget _buildHeader(String storeName) {
    final appProvider = context.read<AppProvider>();
    final countryConfig = appProvider.countryConfig;
    final timezoneDisplay = '${countryConfig.nameCn} · ${countryConfig.timezone}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppConstants.primaryColor, Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(storeName.isNotEmpty ? storeName : '华超管家',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  timezoneDisplay,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // ★ v6.31: 搜索按钮 — 点击弹出商品搜索
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            tooltip: '搜索商品',
            onPressed: () => _showProductSearch(context),
          ),
        ],
      ),
    );
  }

  // ==================== STATS GRID ====================

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    final items = [
      _StatItem('商品总数', '${stats['totalProducts'] ?? 0}', Icons.category,
          Colors.blue, 'products'),
      _StatItem('库存总量', '${stats['totalInventory'] ?? 0}', Icons.inventory,
          Colors.green, 'inventory'),
      _StatItem('今日入库', '${stats['todayInbound'] ?? 0}', Icons.download,
          Colors.orange, 'inbound'),
      _StatItem('今日出库', '${stats['todayOutbound'] ?? 0}', Icons.upload,
          Colors.purple, 'outbound'),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: items.map((item) => _buildStatCard(item)).toList(),
    );
  }

  Widget _buildStatCard(_StatItem item) {
    return InkWell(
      onTap: () => _showStatDetail(context, item.type),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(item.icon, color: item.color, size: 26),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 10),
              Text(item.label,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(item.value,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ALERTS SECTION ====================

  Widget _buildAlertsSection(Map<String, dynamic> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('预警信息',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildAlertCard(
                  '低库存预警',
                  '${stats['lowStockCount'] ?? 0}',
                  Icons.warning,
                  AppConstants.lowStockColor,
                  () => _showAlertDetail(context, 'lowStock')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAlertCard(
                  '临期商品',
                  '${stats['nearExpiry'] ?? 0}',
                  Icons.access_time,
                  AppConstants.warningColor,
                  () => _showAlertDetail(context, 'nearExpiry')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAlertCard(
                  '已过期',
                  '${stats['expired'] ?? 0}',
                  Icons.error,
                  AppConstants.dangerColor,
                  () => _showAlertDetail(context, 'expired')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertCard(String title, String value, IconData icon,
      Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 2),
            Text(title,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  // ==================== PRODUCT SEARCH ====================

  /// ★ v6.31: 看板头部搜索 — 实时搜索商品并显示完整数据
  /// 店长/管理员可见进价，店员/仓库管理员不可见
  void _showProductSearch(BuildContext context) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    final isManager = context.read<AppProvider>().isManager;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.search, color: Colors.blue),
              SizedBox(width: 8),
              Text('搜索商品', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入商品名称或条码...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              setDialogState(() => results = []);
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (keyword) async {
                    if (keyword.trim().isEmpty) {
                      setDialogState(() {
                        results = [];
                        searching = false;
                      });
                      return;
                    }
                    setDialogState(() => searching = true);
                    final db = DatabaseService.instance;
                    final inventory =
                        await db.getInventoryWithProduct(search: keyword.trim());
                    if (ctx.mounted) {
                      setDialogState(() {
                        results = inventory;
                        searching = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (searching)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (results.isEmpty && searchController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('未找到匹配商品', style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                else if (results.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (ctx, index) {
                        final item = results[index];
                        final name = item['name_cn'] as String? ?? '未知';
                        final barcode = item['barcode'] as String? ?? '';
                        final qty = (item['current_quantity'] as num?)?.toInt() ?? 0;
                        final priceCny = (item['price_cny'] as num?)?.toDouble() ?? 0;
                        final priceUzs = (item['price_uzs'] as num?)?.toDouble() ?? 0;
                        final category = item['category'] as String? ?? '';
                        final shelf = item['shelf_location'] as String? ?? '';
                        final costPriceCny = (item['cost_price_cny'] as num?)?.toDouble();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade50,
                              child: Icon(Icons.inventory_2, color: Colors.blue.shade700, size: 20),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(barcode, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                if (category.isNotEmpty)
                                  Text('品类: $category · 货位: ${shelf.isNotEmpty ? shelf : "未分配"}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                // ★ v6.31: 仅店长/管理员可见进价
                                if (isManager && costPriceCny != null && costPriceCny > 0)
                                  Text('进价: ¥${costPriceCny.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatQtyWithUnit(item, qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 2),
                                CurrencyDisplay(
                                  amountCny: priceCny,
                                  amountUzs: priceUzs,
                                  compact: true,
                                ),
                              ],
                            ),
                            onTap: () {
                              final pid = item['product_id'];
                              if (pid != null) {
                                Navigator.pop(ctx);
                                _showProductDetail(pid as int);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  // ==================== STAT DETAIL DIALOG ====================

  /// 统计卡片详情弹窗（商品总数/库存总量/今日入库/今日出库）
  Future<void> _showStatDetail(BuildContext context, String type) async {
    String title;
    List<Map<String, dynamic>> items = [];

    switch (type) {
      case 'products':
        title = '商品总数详情（已入库）';
        final invs =
            await DatabaseService.instance.getInventoryWithProduct();
        for (final i in invs) {
          final qty = i['current_quantity'] ?? 0;
          if (qty <= 0) continue; // ★ 跳过无库存的商品
          items.add({
            'product_id': i['product_id'],
            'name': i['name_cn'] ?? '未知',
            'barcode': i['barcode'] ?? '',
            'qty': qty,
            'unit_big': i['unit_big'],
            'unit_small': i['unit_small'],
            'unit_ratio': i['unit_ratio'],
          });
        }
        break;

      case 'inventory':
        title = '库存总量详情';
        final invs2 =
            await DatabaseService.instance.getInventoryWithProduct();
        for (final i in invs2) {
          final qty = i['current_quantity'] ?? 0;
          if (qty <= 0) continue; // ★ 跳过无库存的商品
          items.add({
            'product_id': i['product_id'],
            'name': i['name_cn'] ?? '未知',
            'barcode': i['barcode'] ?? '',
            'qty': qty,
            'unit_big': i['unit_big'],
            'unit_small': i['unit_small'],
            'unit_ratio': i['unit_ratio'],
          });
        }
        break;

      case 'inbound':
        title = '今日入库详情';
        final today = DateTime.now();
        final start = DateTime(today.year, today.month, today.day);
        final end = start.add(const Duration(days: 1));
        final records = await DatabaseService.instance.getStockRecordsWithName(
            type: StockType.inBound);
        for (final r in records) {
          final createdAt = DateTime.parse(r['created_at'] as String);
          if (createdAt.isAfter(start) && createdAt.isBefore(end)) {
            items.add({
              'product_id': r['product_id'],
              'name': r['name_cn'] ?? '未知',
              'barcode': r['barcode'] ?? '',
              'qty': r['quantity'] ?? 0,
            });
          }
        }
        break;

      case 'outbound':
        title = '今日出库详情';
        final today2 = DateTime.now();
        final start2 = DateTime(today2.year, today2.month, today2.day);
        final end2 = start2.add(const Duration(days: 1));
        final records2 = await DatabaseService.instance
            .getStockRecordsWithName(type: StockType.outBound);
        for (final r in records2) {
          final createdAt = DateTime.parse(r['created_at'] as String);
          if (createdAt.isAfter(start2) && createdAt.isBefore(end2)) {
            items.add({
              'product_id': r['product_id'],
              'name': r['name_cn'] ?? '未知',
              'barcode': r['barcode'] ?? '',
              'qty': r['quantity'] ?? 0,
            });
          }
        }
        break;

      default:
        return;
    }

    if (!mounted) return;
    _showListDetailDialog(title, items);
  }

  // ==================== ALERT DETAIL DIALOG ====================

  /// 预警卡片详情弹窗（低库存/临期/已过期）
  Future<void> _showAlertDetail(BuildContext context, String type) async {
    String title;
    List<Map<String, dynamic>> items = [];
    bool isBatch = false; // 是否是批次级别显示

    switch (type) {
      case 'lowStock':
        title = '低库存预警商品';
        final results =
            await DatabaseService.instance.getLowStockWithName();
        for (final i in results) {
          items.add({
            'product_id': i['product_id'],
            'name': i['name_cn'] ?? '未知',
            'barcode': i['barcode'] ?? '',
            'qty': i['current_quantity'] ?? 0,
            'min_stock': i['min_stock_level'] ?? 10,
            'subtitle_extra':
                '预警线: ${i['min_stock_level'] ?? 10}',
          });
        }
        break;

      case 'nearExpiry':
        title = '临期商品（30天内到期，按批次）';
        isBatch = true;
        final results =
            await DatabaseService.instance.getBatchNearExpiry();
        for (final r in results) {
          final daysRemaining =
              (r['days_remaining'] as num?)?.toInt() ?? 0;
          final qty = (r['total_qty'] as num?)?.toInt() ?? 0;
          items.add({
            'product_id': r['product_id'],
            'name': r['name_cn'] ?? '未知',
            'barcode': r['barcode'] ?? '',
            'qty': qty,
            'days_remaining': daysRemaining,
            'expiry_date': r['expiry_date'] ?? '',
            'subtitle_extra': '剩${-daysRemaining}天 · 库存$qty',
          });
        }
        break;

      case 'expired':
        title = '已过期商品（按批次）';
        isBatch = true;
        final results =
            await DatabaseService.instance.getBatchExpired();
        for (final r in results) {
          final daysExpired =
              (r['days_expired'] as num?)?.toInt() ?? 0;
          final qty = (r['total_qty'] as num?)?.toInt() ?? 0;
          items.add({
            'product_id': r['product_id'],
            'name': r['name_cn'] ?? '未知',
            'barcode': r['barcode'] ?? '',
            'qty': qty,
            'days_expired': daysExpired,
            'expiry_date': r['expiry_date'] ?? '',
            'subtitle_extra': '已过期${daysExpired}天 · 库存$qty',
          });
        }
        break;

      default:
        return;
    }

    if (!mounted) return;
    _showListDetailDialog(title, items, isBatch: isBatch, alertType: type);
  }

  // ==================== 通用列表详情弹窗 ====================

  /// 通用的列表详情弹窗，支持点击项目查看商品详情
  void _showListDetailDialog(String title, List<Map<String, dynamic>> items,
      {bool isBatch = false, String? alertType}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title (共${items.length}项)',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: items.isEmpty
              ? const Center(child: Text('暂无数据'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final name = item['name'] as String? ?? '未知';
                    final barcode =
                        item['barcode'] as String? ?? '';
                    final qty =
                        (item['qty'] as num?)?.toInt() ?? 0;
                    final subtitleExtra =
                        item['subtitle_extra'] as String? ?? '';

                    // 批次级别显示特殊格式
                    final qtyDisplay = _formatQtyWithUnit(item, qty);
                    String subtitle;
                    if (isBatch && alertType == 'nearExpiry') {
                      final days =
                          (item['days_remaining'] as num?)?.toInt() ?? 0;
                      subtitle =
                          '$barcode · 剩${-days}天 · 库存$qtyDisplay';
                    } else if (isBatch && alertType == 'expired') {
                      final days =
                          (item['days_expired'] as num?)?.toInt() ?? 0;
                      subtitle =
                          '$barcode · 已过期${days}天 · 库存$qtyDisplay';
                    } else if (subtitleExtra.isNotEmpty) {
                      subtitle = '$barcode · $subtitleExtra';
                    } else {
                      subtitle = '$barcode · 数量: $qtyDisplay';
                    }

                    // 颜色标记
                    Color? bgColor;
                    if (alertType == 'nearExpiry') {
                      final days =
                          (item['days_remaining'] as num?)?.toInt() ?? 0;
                      if (-days <= 3) {
                        bgColor = Colors.orange.shade50;
                      }
                    } else if (alertType == 'expired') {
                      bgColor = Colors.red.shade50;
                    }

                    return Container(
                      color: bgColor,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade200,
                          child: Text('${index + 1}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(subtitle,
                            style: const TextStyle(fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(qtyDisplay,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            // ★ 临期/过期项目可编辑数量
                            if (isBatch &&
                                (alertType == 'nearExpiry' ||
                                    alertType == 'expired'))
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 18, color: Colors.blue),
                                onPressed: () => _editBatchQuantity(
                                    item, alertType!),
                              ),
                          ],
                        ),
                        onTap: () {
                          final pid = item['product_id'];
                          if (pid != null) {
                            _showProductDetail(pid as int);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  // ==================== 编辑批次数量 ====================

  /// ★ 编辑临期/过期批次的实际数量
  /// 用户可以修正数量（如部分售出未走系统、损坏等）
  void _editBatchQuantity(Map<String, dynamic> item, String alertType) {
    final nameCn = item['name'] as String? ?? '未知';
    final productId = item['product_id'] as int;
    final barcode = item['barcode'] as String? ?? '';
    final oldQty = (item['qty'] as num?)?.toInt() ?? 0;
    final expiryDate = item['expiry_date'] as String? ?? '';

    final qtyController = TextEditingController(text: '$oldQty');
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('调整 $nameCn 数量'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('条码: $barcode',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (expiryDate.isNotEmpty)
                Text('保质期: $expiryDate',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('当前系统数量: $oldQty',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '实际数量',
                  prefixIcon: Icon(Icons.format_list_numbered),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: '调整原因 (可选)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '减少数量 = 商品已出售/损坏/丢弃\n增加数量 = 发现遗漏/退货入库',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newQty = int.tryParse(qtyController.text) ?? oldQty;
              final diff = newQty - oldQty;

              if (diff == 0) {
                Navigator.pop(ctx);
                return;
              }

              final db = DatabaseService.instance;
              final reason = reasonController.text.isNotEmpty
                  ? reasonController.text
                  : (diff < 0 ? '手动调整减少' : '手动调整增加');

              // 获取商品信息
              final product = await db.getProductById(productId);
              if (product == null) {
                Navigator.pop(ctx);
                return;
              }

              if (diff < 0) {
                // ★ 数量减少 → 创建出库记录
                final record = StockRecord(
                  productId: productId,
                  barcode: barcode,
                  type: StockType.outBound,
                  quantity: -diff,
                  priceCny: product.priceCny,
                  priceUzs: product.priceUzs,
                  outboundReason: OutboundReason.other,
                  operatorName: '系统调整',
                  note: '$reason (原${oldQty}→$newQty)',
                );
                await context
                    .read<InventoryProvider>()
                    .recordStockOut(record);
              } else {
                // ★ 数量增加 → 创建入库记录
                final expiryDt = expiryDate.isNotEmpty
                    ? DateTime.tryParse(expiryDate)
                    : null;
                final record = StockRecord(
                  productId: productId,
                  barcode: barcode,
                  type: StockType.inBound,
                  quantity: diff,
                  priceCny: product.priceCny,
                  priceUzs: product.priceUzs,
                  operatorName: '系统调整',
                  note: '$reason (原${oldQty}→$newQty)',
                  expiryDate: expiryDt,
                );
                await context
                    .read<InventoryProvider>()
                    .recordStockIn(record);
              }

              Navigator.pop(ctx); // 关闭编辑弹窗
              Navigator.pop(context); // 关闭列表弹窗

              // 刷新看板
              await context
                  .read<InventoryProvider>()
                  .loadDashboardStats();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '$nameCn 数量已调整: $oldQty → $newQty'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('确认调整'),
          ),
        ],
      ),
    );
  }

  // ==================== 商品详情弹窗 ====================

  /// 商品详情弹窗（点击列表项后显示）
  Future<void> _showProductDetail(int productId) async {
    final detail =
        await DatabaseService.instance.getProductDetail(productId);
    if (detail == null) return;
    if (!mounted) return;
    final currencySymbol = context.read<AppProvider>().countryConfig.currencySymbol;
    final isManager = context.read<AppProvider>().isManager;

    final nameCn = detail['name_cn'] as String? ?? '未知商品';
    final barcode = detail['barcode'] as String? ?? '';
    final category = detail['category'] as String? ?? '';
    final priceCny = (detail['price_cny'] as num?)?.toDouble() ?? 0;
    final priceUzs = (detail['price_uzs'] as num?)?.toDouble() ?? 0;
    final totalStock = (detail['totalStock'] as num?)?.toInt() ?? 0;
    final minStock = (detail['minStock'] as num?)?.toInt() ?? 10;
    final expiryDate = detail['expiry_date'] as String?;
    final batches = detail['batches'] as List<dynamic>? ?? [];

    // 统计临期和过期批次
    int nearExpiryQty = 0;
    int expiredQty = 0;
    for (final b in batches) {
      final daysRemaining =
          (b['days_remaining'] as num?)?.toInt() ?? 0;
      final batchQty = (b['batch_qty'] as num?)?.toInt() ?? 0;
      if (daysRemaining < 0) {
        // 已过期
        expiredQty += batchQty;
      } else if (daysRemaining <= 7) {
        nearExpiryQty += batchQty;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(nameCn,
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 基本信息
                _detailRow('条码', barcode),
                _detailRow('品类', category),
                // ★ v6.31: 仅店长/管理员可见进价
                if (isManager)
                _detailRow('进价', '¥${priceCny.toStringAsFixed(2)}'),
                _detailRow('售价', '${priceUzs.toStringAsFixed(0)} $currencySymbol'),
                const Divider(height: 20),

                // 库存信息
                _detailRow('当前库存', '$totalStock',
                    valueColor: totalStock <= minStock
                        ? Colors.red
                        : Colors.green),
                _detailRow('预警线', '$minStock'),
                if (expiryDate != null && expiryDate.isNotEmpty)
                  _detailRow('保质期至', expiryDate),
                const Divider(height: 20),

                // 临期/过期统计
                Row(
                  children: [
                    Expanded(
                      child: _miniStatCard(
                          '临期', '$nearExpiryQty', Colors.orange),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniStatCard(
                          '已过期', '$expiredQty', Colors.red),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniStatCard(
                          '正常', '${totalStock - nearExpiryQty - expiredQty}',
                          Colors.green),
                    ),
                  ],
                ),

                // 批次明细
                if (batches.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('保质期批次明细',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...batches.map((b) {
                    final expiryStr =
                        b['expiry_date'] as String? ?? '';
                    final batchQty =
                        (b['batch_qty'] as num?)?.toInt() ?? 0;
                    final daysRemaining =
                        (b['days_remaining'] as num?)?.toInt() ?? 0;

                    String statusText;
                    Color statusColor;
                    if (daysRemaining < 0) {
                      statusText = '已过期${-daysRemaining}天';
                      statusColor = Colors.red;
                    } else if (daysRemaining == 0) {
                      statusText = '今天到期';
                      statusColor = Colors.orange;
                    } else if (daysRemaining <= 7) {
                      statusText = '剩${daysRemaining}天';
                      statusColor = Colors.orange;
                    } else {
                      statusText = '剩${daysRemaining}天';
                      statusColor = Colors.green;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('到期: $expiryStr',
                                style:
                                    const TextStyle(fontSize: 13)),
                          ),
                          Text('$batchQty 件',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Text(statusText,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 详情行组件
  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }

  /// 迷你统计卡片（用于商品详情弹窗内的临期/过期/正常统计）
  Widget _miniStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String type;
  _StatItem(this.label, this.value, this.icon, this.color, this.type);
}
