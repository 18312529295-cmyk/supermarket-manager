import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../config/constants.dart';
import '../../utils/currency_util.dart';
import '../../utils/date_util.dart';
import 'dashboard_tab.dart';
import 'inventory_list_tab.dart';
import 'expiry_alert_tab.dart';

class InventoryScreen extends StatefulWidget {
  final bool offlineView;
  const InventoryScreen({super.key, this.offlineView = false});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        // 切到"看板"Tab时刷新统计数据
        context.read<InventoryProvider>().loadDashboardStats();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadDashboardStats();
      context.read<InventoryProvider>().loadInventory();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.offlineView ? '离线库存' : '库存管理'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '看板', icon: Icon(Icons.dashboard_outlined, color: Colors.white)),
            Tab(text: '库存列表', icon: Icon(Icons.list_alt, color: Colors.white)),
            Tab(text: '临期预警', icon: Icon(Icons.warning_amber, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Open search
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          DashboardTab(),
          InventoryListTab(),
          ExpiryAlertTab(),
        ],
      ),
    );
  }
}
