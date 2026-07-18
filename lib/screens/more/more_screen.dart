import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_provider.dart';
import '../shelf/shelf_screen.dart';
import '../listing/listing_screen.dart';
import '../user/user_screen.dart';
import '../settings/settings_screen.dart';
import '../check/check_report_screen.dart';
import '../inventory/inventory_screen.dart';
import '../auth/login_screen.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isManager = appProvider.isManager;

    return Scaffold(
      appBar: AppBar(
        title: const Text('更多功能'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSectionTitle('库存管理'),
          _buildMenuCard(
            context,
            icon: Icons.shelves,
            title: '货架管理',
            subtitle: '货位定位 · 商品-货架绑定 · 快速找货',
            color: Colors.indigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShelfScreen()),
            ),
          ),
          if (isManager)
            _buildMenuCard(
              context,
              icon: Icons.attach_money,
              title: '上架管理',
              subtitle: '商品定价 · 货架分配 · 进价售价双币种',
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ListingScreen()),
              ),
            ),
          _buildMenuCard(
            context,
            icon: Icons.bar_chart,
            title: '差异报表',
            subtitle: '盘点结果分析 · 盘盈/盘亏统计 · 差异趋势图',
            color: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckReportScreen()),
            ),
          ),
          if (isManager) ...[
            const SizedBox(height: 16),
            _buildSectionTitle('人员与权限'),
            _buildMenuCard(
              context,
              icon: Icons.people,
              title: '人员管理',
              subtitle: '权限管理 · 操作记录追溯',
              color: Colors.deepPurple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserScreen()),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildSectionTitle('数据同步'),
          _buildMenuCard(
            context,
            icon: Icons.cloud_off,
            title: '离线库存',
            subtitle: '查看本地存储的库存数据 · 离线模式下仍可操作',
            color: Colors.amber.shade700,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InventoryScreen(offlineView: true)),
            ),
          ),
          _buildMenuCard(
            context,
            icon: Icons.cloud_sync,
            title: '云端同步',
            subtitle: '上传出入库 · 下载商品库 · 同步盘点差异',
            color: const Color(0xFF1565C0),
            onTap: () => _startSync(context),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('系统'),
          if (isManager)
            _buildMenuCard(
              context,
              icon: Icons.settings,
              title: '系统设置',
              subtitle: '语言 · 货币 · 时区 · 条码 · 网络同步',
              color: Colors.grey.shade700,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          _buildMenuCard(
            context,
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '华人超市管家 v6.31.0',
            color: Colors.blueGrey,
            onTap: () => _showAboutDialog(context),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('账户'),
          _buildMenuCard(
            context,
            icon: Icons.logout,
            title: '退出登录',
            subtitle: '当前用户: ${appProvider.currentUser.isNotEmpty ? appProvider.currentUser : '未知'}',
            color: Colors.red,
            onTap: () => _confirmLogout(context, appProvider),
          ),
        ],
      ),
    );
  }

  Future<void> _startSync(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('正在同步...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    final syncService = SyncService();
    final result = await syncService.syncPendingRecords();

    // ★ v6.32 (方案C): 同步后检查国家配置是否有更新
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncedCountry = prefs.getString('country_code') ?? 'CN';
      final appProvider = context.read<AppProvider>();
      if (appProvider.countryCode != syncedCountry) {
        await appProvider.setCountry(syncedCountry);
        debugPrint('[MoreScreen] country_code synced: ${appProvider.countryCode} → $syncedCountry');
      }
    } catch (_) {}

    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppProvider appProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后需要重新登录才能使用系统。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await appProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              '华人超市管家',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('版本: 6.31.0'),
            SizedBox(height: 8),
            Text(
              '专为乌兹别克斯坦华人超市设计\n支持多语言 · 离线模式 · 双币显示',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
        ],
      ),
    );
  }
}
