import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/inventory_provider.dart';
import 'inventory/inventory_screen.dart';
import 'stock_in/stock_in_screen.dart';
import 'stock_out/stock_out_screen.dart';
import 'check/check_screen.dart';
import 'more/more_screen.dart';
import 'auth/login_screen.dart';
import 'sales/sales_analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _syncTriggered = false;
  bool _isActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_syncTriggered && mounted) {
      _syncTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ★ v6.32: 传 AppProvider 给 InventoryProvider，用于同步后刷新国家配置
        context.read<InventoryProvider>().setAppProvider(context.read<AppProvider>());
        _triggerSync();
        // ★ 开启定时轮询：每30秒自动同步一次云端数据
        _startPollingSync();
      });
    }
  }

  /// 触发一次云端同步（不阻塞UI）
  Future<void> _triggerSync() async {
    final result = await context.read<InventoryProvider>().syncPendingData();
    if (mounted && !result.success) {
      // 同步失败则5秒后重试一次
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isActive) {
          context.read<InventoryProvider>().syncPendingData();
        }
      });
    }
  }

  /// ★ 每30秒自动同步一次库存，确保两台手机的库存接近实时
  void _startPollingSync() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 30));
      if (!mounted || !_isActive) return false;
      _triggerSync();
      return _isActive;
    });
  }

  @override
  void dispose() {
    _isActive = false;
    super.dispose();
  }

  /// ★ 登出确认弹窗
  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后需要重新登录才能使用系统。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppProvider>().logout();
              if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isManager = appProvider.isManager;

    final List<Widget> pages = [
      const InventoryScreen(),
      const StockInScreen(),
      const StockOutScreen(),
      const CheckScreen(),
      const SalesAnalysisScreen(),
      if (isManager) const MoreScreen() else const SizedBox.shrink(),
    ];

    final List<NavigationItem> navItems = [
      NavigationItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: '库存'),
      NavigationItem(icon: Icons.download_outlined, activeIcon: Icons.download, label: '入库'),
      NavigationItem(icon: Icons.upload_outlined, activeIcon: Icons.upload, label: '出库'),
      NavigationItem(icon: Icons.fact_check_outlined, activeIcon: Icons.fact_check, label: '盘点'),
      NavigationItem(icon: Icons.analytics_outlined, activeIcon: Icons.analytics, label: '销售分析'),
      if (isManager) NavigationItem(icon: Icons.menu_outlined, activeIcon: Icons.menu, label: '更多'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          appProvider.currentUser.isNotEmpty ? '${appProvider.currentUser}' : '超市管家',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          // ★ 登出按钮 — 所有用户可见
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: navItems.map((item) {
          return BottomNavigationBarItem(
            icon: Icon(item.icon),
            activeIcon: Icon(item.activeIcon),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  NavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
