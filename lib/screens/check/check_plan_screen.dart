import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../services/database_service.dart';
import '../../models/check_task.dart';
import '../../models/shelf.dart';
import '../../models/user.dart';

/// ★ v6.16 盘点规划页面：店长按货架分配盘点任务给不同员工
class CheckPlanScreen extends StatefulWidget {
  const CheckPlanScreen({super.key});

  @override
  State<CheckPlanScreen> createState() => _CheckPlanScreenState();
}

class _CheckPlanScreenState extends State<CheckPlanScreen> {
  final _planNameController = TextEditingController(text: _defaultPlanName());
  List<Shelf> _shelves = [];
  List<User> _users = [];
  bool _loading = true;

  // 每个货架 code → 分配给哪个员工 username
  final Map<String, String?> _assignment = {};
  /// ★ v6.27: 每个货架 code → 商品数（库存>0）
  Map<String, int> _shelfProductCounts = {};

  static String _defaultPlanName() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_盘点';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final shelves = await DatabaseService.instance.getAllShelves();
    final users = await DatabaseService.instance.getAllUsers();
    // ★ v6.27: 统计每个货架上的商品数
    final db = DatabaseService.instance;
    final counts = <String, int>{};
    final result = await db.rawQuery('''
      SELECT i.shelf_location, COUNT(*) as cnt
      FROM inventory i
      WHERE i.current_quantity > 0 AND i.shelf_location IS NOT NULL AND i.shelf_location != ''
      GROUP BY i.shelf_location
    ''');
    for (final r in result) {
      counts[r['shelf_location'] as String] = (r['cnt'] as num).toInt();
    }
    _shelfProductCounts = counts;
    // 初始化：默认全部分配给第一个人
    final firstUser = users.isNotEmpty ? users.first.username : null;
    for (final s in shelves) {
      _assignment[s.code] = firstUser;
    }
    setState(() {
      _shelves = shelves;
      _users = users;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('盘点规划')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 计划名称
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _planNameController,
                    decoration: const InputDecoration(
                      labelText: '计划名称',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_calendar),
                    ),
                  ),
                ),
                // 货架列表 + 分配
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildUserLegend(),
                      const SizedBox(height: 12),
                      ..._groupShelvesByZone().entries.map((entry) {
                        final zone = entry.key;
                        final zoneShelves = entry.value;
                        return _buildZoneGroup(zone, zoneShelves);
                      }),
                    ],
                  ),
                ),
                // 底部生成按钮
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _users.isEmpty ? null : _generateTasks,
                        icon: const Icon(Icons.assignment_turned_in),
                        label: const Text('生成分配任务', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildUserLegend() {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal, Colors.red];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: _users.asMap().entries.map((e) {
        final i = e.key;
        final u = e.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: colors[i % colors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(u.displayName, style: const TextStyle(fontSize: 13)),
          ],
        );
      }).toList(),
    );
  }

  Map<String, List<Shelf>> _groupShelvesByZone() {
    final map = <String, List<Shelf>>{};
    for (final s in _shelves) {
      map.putIfAbsent(s.zone, () => []);
      map[s.zone]!.add(s);
    }
    return map;
  }

  Widget _buildZoneGroup(String zone, List<Shelf> shelves) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal, Colors.red];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warehouse, size: 18),
              const SizedBox(width: 6),
              Text(zone, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              // 快捷操作：整区分给某人
              PopupMenuButton<String>(
                icon: const Icon(Icons.person_add, size: 18),
                tooltip: '整区分配给',
                onSelected: (username) {
                  setState(() {
                    for (final s in shelves) {
                      _assignment[s.code] = username;
                    }
                  });
                },
                itemBuilder: (_) => _users.map((u) => PopupMenuItem(
                  value: u.username,
                  child: Text(u.displayName),
                )).toList(),
              ),
            ]),
            const SizedBox(height: 8),
            ...shelves.map((s) => _buildShelfRow(s, colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfRow(Shelf shelf, List<Color> colors) {
    final assignedUser = _assignment[shelf.code];
    final productCount = _shelfProductCounts[shelf.code] ?? 0;
    return InkWell(
      onTap: () => _pickUser(shelf),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(shelf.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(shelf.name, style: const TextStyle(fontSize: 14))),
            // ★ v6.27: 显示商品数
            if (productCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$productCount件', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
              ),
            ],
            // 当前分配的人
            if (assignedUser != null) ...[
              _buildAssignedChip(assignedUser, colors),
            ] else
              TextButton(
                onPressed: () => _pickUser(shelf),
                child: const Text('分配', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedChip(String username, List<Color> colors) {
    final userIndex = _users.indexWhere((u) => u.username == username);
    final color = userIndex >= 0 ? colors[userIndex % colors.length] : Colors.grey;
    final displayName = userIndex >= 0 ? _users[userIndex].displayName : username;
    return GestureDetector(
      onTap: () => _pickUserByUsername(username),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(displayName, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  void _pickUser(Shelf shelf) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${shelf.name} (${shelf.code}) 分配给',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ..._users.map((u) => ListTile(
            leading: CircleAvatar(
              child: Text(u.displayName[0]),
            ),
            title: Text(u.displayName),
            subtitle: Text(u.role.displayName),
            onTap: () {
              setState(() => _assignment[shelf.code] = u.username);
              Navigator.pop(ctx);
            },
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _pickUserByUsername(String currentUsername) {
    final shelfCodes = _assignment.entries
        .where((e) => e.value == currentUsername)
        .map((e) => e.key)
        .toList();
    final shelf = _shelves.firstWhere(
      (s) => shelfCodes.contains(s.code),
      orElse: () => _shelves.first,
    );
    _pickUser(shelf);
  }

  Future<void> _generateTasks() async {
    final planName = _planNameController.text.trim();
    if (planName.isEmpty || _users.isEmpty) return;

    // 按人员分组货架
    final userShelves = <String, List<String>>{};
    for (final u in _users) {
      userShelves[u.username] = [];
    }
    for (final e in _assignment.entries) {
      if (e.value != null && userShelves.containsKey(e.value)) {
        userShelves[e.value]!.add(e.key);
      }
    }

    // 为每个有货架的员工创建盘点任务
    int created = 0;
    for (final u in _users) {
      final codes = userShelves[u.username]!;
      if (codes.isEmpty) continue;

      final task = CheckTask(
        title: '$planName - ${u.displayName}',
        operatorName: u.username,
        shelfFilter: codes.join(','),
        assignedTo: u.username,
      );
      await context.read<InventoryProvider>().createCheckTask(task);
      created++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已创建 $created 个盘点任务'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context, true);
  }
}
