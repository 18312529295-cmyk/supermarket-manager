import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../config/country_config.dart';

/// ==========================================================
/// 共享的商品详情弹窗工具
/// 可在入库、出库、看板等界面调用
/// ==========================================================

/// 显示商品详情弹窗（含批次信息、库存、价格等）
Future<void> showProductDetailDialog(BuildContext context, int productId, {String currencySymbol = 'so\'m'}) async {
  final detail = await DatabaseService.instance.getProductDetail(productId);
  if (detail == null) return;
  if (!context.mounted) return;

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
    final daysRemaining = (b['days_remaining'] as num?)?.toInt() ?? 0;
    final batchQty = (b['batch_qty'] as num?)?.toInt() ?? 0;
    if (daysRemaining < 0) {
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
              _detailRow('条码', barcode),
              _detailRow('品类', category),
              _detailRow('进价', '¥${priceCny.toStringAsFixed(2)}'),
              _detailRow('售价', '${priceUzs.toStringAsFixed(0)} $currencySymbol'),
              const Divider(height: 20),
              _detailRow('当前库存', '$totalStock',
                  valueColor:
                      totalStock <= minStock ? Colors.red : Colors.green),
              _detailRow('预警线', '$minStock'),
              if (expiryDate != null && expiryDate.isNotEmpty)
                _detailRow('保质期至', expiryDate),
              const Divider(height: 20),

              // 临期/过期统计
              Row(
                children: [
                  Expanded(
                    child: _miniStatCard('临期', '$nearExpiryQty', Colors.orange),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniStatCard('已过期', '$expiredQty', Colors.red),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniStatCard(
                        '正常', '${totalStock - nearExpiryQty - expiredQty}', Colors.green),
                  ),
                ],
              ),

              // 批次明细
              if (batches.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('保质期批次明细',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...batches.map((b) {
                  final expiryStr = b['expiry_date'] as String? ?? '';
                  final batchQty = (b['batch_qty'] as num?)?.toInt() ?? 0;
                  final daysRemaining = (b['days_remaining'] as num?)?.toInt() ?? 0;

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('到期: $expiryStr',
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text('$batchQty 件',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusText,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
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

Widget _detailRow(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    ),
  );
}
