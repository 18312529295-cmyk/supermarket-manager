import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../config/constants.dart';
import '../../utils/date_util.dart';

class ExpiryAlertTab extends StatefulWidget {
  const ExpiryAlertTab({super.key});

  @override
  State<ExpiryAlertTab> createState() => _ExpiryAlertTabState();
}

class _ExpiryAlertTabState extends State<ExpiryAlertTab> {
  int _filterDays = 7;

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, provider, child) {
        final items = provider.inventoryList.where((item) {
          final expiryStr = item['expiry_date'] as String?;
          if (expiryStr == null) return false;
          final expiry = DateTime.parse(expiryStr);
          final days = expiry.difference(DateTime.now()).inDays;
          return days <= _filterDays;
        }).toList();

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Row(
                children: [
                  const Text('预警天数:'),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('7天'),
                    selected: _filterDays == 7,
                    onSelected: (_) => setState(() => _filterDays = 7),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('15天'),
                    selected: _filterDays == 15,
                    onSelected: (_) => setState(() => _filterDays = 15),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('30天'),
                    selected: _filterDays == 30,
                    onSelected: (_) => setState(() => _filterDays = 30),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('已过期', style: TextStyle(color: Colors.red)),
                    selected: _filterDays == -1,
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) => setState(() => _filterDays = -1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('暂无临期/过期商品'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return _buildExpiryCard(items[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExpiryCard(Map<String, dynamic> item) {
    final name = item['name_cn'] as String? ?? '';
    final nameRu = item['name_ru'] as String?;
    final qty = item['current_quantity'] as int? ?? 0;
    final expiryStr = item['expiry_date'] as String?;
    final expiry = expiryStr != null ? DateTime.parse(expiryStr) : null;
    final daysLeft = expiry != null ? expiry.difference(DateTime.now()).inDays : null;

    Color statusColor = Colors.green;
    String statusText = '';

    if (daysLeft == null) {
      statusColor = Colors.grey;
      statusText = '未知';
    } else if (daysLeft < 0) {
      statusColor = AppConstants.dangerColor;
      statusText = '已过期 ${-daysLeft} 天';
    } else if (daysLeft == 0) {
      statusColor = AppConstants.dangerColor;
      statusText = '今天过期';
    } else if (daysLeft <= 30) {
      statusColor = AppConstants.warningColor;
      statusText = '剩 $daysLeft 天';
    } else {
      statusColor = Colors.blue;
      statusText = '剩 $daysLeft 天';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(Icons.access_time, color: statusColor, size: 20),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nameRu != null && nameRu.isNotEmpty)
              Text(nameRu, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              '库存: $qty  |  过期日: ${expiry != null ? DateUtil.formatDate(expiry) : '-'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
