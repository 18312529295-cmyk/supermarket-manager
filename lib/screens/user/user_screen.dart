import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../models/user.dart';
import '../../services/database_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../utils/date_util.dart';
import '../../utils/password_util.dart';

/// ==========================================================
/// 人员管理界面
/// 功能：
///   1. 显示员工列表（含手机号和PIN码）
///   2. 新增员工时自动生成PIN码，可手动修改
///   3. 支持重置员工PIN码
///   4. 操作记录查看
/// ==========================================================
class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>();
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
        title: const Text('人员管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '员工列表', icon: Icon(Icons.people)),
            Tab(text: '操作记录', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserListTab(),
          _buildOperationLogTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.person_add),
        label: const Text('新增员工'),
      ),
    );
  }

  Widget _buildUserListTab() {
    return FutureBuilder<List<User>>(
      future: DatabaseService.instance.getAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('暂无员工'));
        }

        final users = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return _buildUserCard(user);
            },
          ),
        );
      },
    );
  }

  /// ★ 构建单个员工卡片（含PIN码显示和重置按钮）
  Widget _buildUserCard(User user) {
    final pin = user.passwordHash != null ? '已设置' : '未设置';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getRoleColor(user.role).withOpacity(0.2),
                  child: Icon(Icons.person, color: _getRoleColor(user.role)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text('${user.username} · ${user.role.displayName}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                user.isActive
                    ? const Chip(
                        label: Text('在职', style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.green,
                        labelStyle: TextStyle(color: Colors.white),
                        padding: EdgeInsets.zero,
                      )
                    : const Chip(
                        label: Text('停用', style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.grey,
                        labelStyle: TextStyle(color: Colors.white),
                        padding: EdgeInsets.zero,
                      ),
              ],
            ),
            const SizedBox(height: 8),
            // ★ 手机号和PIN码信息行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_android, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    user.phone != null && user.phone!.isNotEmpty ? user.phone! : '未绑定手机',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.pin, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  const Text('PIN: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  // ★ PIN码显示（可点击复制）
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: pin));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('PIN码已复制'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pin,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('(点击复制)', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // ★ 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重置PIN', style: TextStyle(fontSize: 12)),
                  onPressed: () => _resetPin(user),
                ),
                TextButton.icon(
                  icon: Icon(user.isActive ? Icons.block : Icons.check_circle, size: 16),
                  label: Text(user.isActive ? '停用' : '启用', style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: user.isActive ? Colors.orange : Colors.green,
                  ),
                  onPressed: () async {
                    await DatabaseService.instance.toggleUserActive(user.id!, !user.isActive);
                    setState(() {});
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('修改', style: TextStyle(fontSize: 12)),
                  onPressed: () => _editUser(user),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red.shade300),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定删除${user.displayName}？此操作不可恢复'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('取消'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () async {
                              await DatabaseService.instance.deleteUser(user.id!);
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                            child: const Text('删除', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ★ 重置员工PIN码
  void _resetPin(User user) {
    final newPinController = TextEditingController(text: DatabaseService.generatePin());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重置 ${user.displayName} 的PIN码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前PIN: ${user.passwordHash != null ? "已设置" : "未设置"}',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            TextField(
              controller: newPinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '新PIN码 (4-6位数字)',
                prefixIcon: Icon(Icons.pin),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '员工使用手机号 + PIN码登录',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              newPinController.text = DatabaseService.generatePin();
            },
            child: const Text('随机生成'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final pin = newPinController.text.trim();
              if (pin.length < 4 || pin.length > 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN码须为4-6位数字')),
                );
                return;
              }
              await DatabaseService.instance.updateUserPin(user.id!, pin);
              Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${user.displayName} 的PIN码已更新为: $pin'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 编辑员工信息（修改手机号和PIN码）
  void _editUser(User user) {
    final phoneController = TextEditingController(text: user.phone ?? '');
    final pinController = TextEditingController();  // ★ v6.31: 不再回显旧的PIN，管理员直接输入新PIN

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${user.displayName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('用户名: ${user.username}',
                  style: TextStyle(color: Colors.grey.shade600)),
              Text('角色: ${user.role.displayName}',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'PIN码 (用于手机号登录)',
                  prefixIcon: Icon(Icons.pin),
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newPin = pinController.text.trim();
              final updatedUser = user.copyWith(
                phone: phoneController.text.trim().isNotEmpty
                    ? phoneController.text.trim()
                    : null,
              );
              final db = await DatabaseService.instance.database;
              await db.update('users', updatedUser.toMap(),
                  where: 'id = ?', whereArgs: [user.id]);
              // ★ v6.31: 如果设置了新PIN，用哈希存储
              if (newPin.isNotEmpty && user.id != null) {
                await DatabaseService.instance.updateUserPin(user.id!, newPin);
              }
              Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('${user.displayName} 信息已更新'),
                      backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationLogTab() {
    return FutureBuilder<List<OperationLog>>(
      future: DatabaseService.instance.getOperationLogs(limit: 100),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data!;
        if (logs.isEmpty) {
          return const Center(child: Text('暂无操作记录'));
        }

        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade200,
                  child: Text(log.username.substring(0, 1),
                      style: const TextStyle(fontSize: 12)),
                ),
                title: Text(log.action,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (log.detail != null)
                      Text(log.detail!, style: const TextStyle(fontSize: 12)),
                    if (log.barcode != null)
                      Text('条码: ${log.barcode}',
                          style: const TextStyle(fontSize: 11)),
                    Text(
                      '${log.username} · ${DateUtil.formatDateTime(log.createdAt)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                isThreeLine: log.detail != null && log.detail!.length > 20,
              ),
            );
          },
        );
      },
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.manager:
        return Colors.orange;
      case UserRole.cashier:
        return Colors.blue;
      case UserRole.stockKeeper:
        return Colors.green;
    }
  }

  /// ★ 新增员工（自动生成PIN码）
  void _addUser() {
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final phoneController = TextEditingController();
    final pinController =
        TextEditingController(text: DatabaseService.generatePin());
    UserRole selectedRole = UserRole.cashier;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('新增员工'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                      labelText: '用户名 *', helperText: '用于账号密码登录'),
                ),
                TextField(
                  controller: displayNameController,
                  decoration: const InputDecoration(labelText: '显示名称 *'),
                ),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    helperText: '员工使用手机号 + PIN码登录',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                // ★ PIN码设置区域
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pin,
                              color: Colors.orange, size: 20),
                          const SizedBox(width: 6),
                          const Text('PIN码 (手机号登录用)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                pinController.text =
                                    DatabaseService.generatePin();
                              });
                            },
                            child: const Text('随机生成',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      TextField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '4-6位数字',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        style: const TextStyle(
                            fontSize: 18,
                            letterSpacing: 3,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: '角色 *'),
                  items: UserRole.values.where((r) => r != UserRole.admin).map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (usernameController.text.isEmpty ||
                    displayNameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('用户名和显示名称不能为空')),
                  );
                  return;
                }
                final pin = pinController.text.trim();
                if (pin.length < 4 || pin.length > 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN码须为4-6位数字')),
                  );
                  return;
                }
                // ★ v6.31: 密码哈希存储
                final userSalt = PasswordUtil.generateSalt();
                final userHash = PasswordUtil.hashPassword(pin, userSalt);
                final user = User(
                  username: usernameController.text,
                  displayName: displayNameController.text,
                  passwordHash: userHash,
                  passwordSalt: userSalt,
                  role: selectedRole,
                  phone: phoneController.text.trim().isNotEmpty
                      ? phoneController.text.trim()
                      : null,
                );
                await DatabaseService.instance.insertUser(user);

                // ★ 同步新用户到云端
                try {
                  final syncService = SupabaseSyncService();
                  syncService.uploadUser(user);
                } catch (_) {}

                Navigator.pop(dialogCtx);
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          '已添加 ${user.displayName}，PIN码: $pin'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
