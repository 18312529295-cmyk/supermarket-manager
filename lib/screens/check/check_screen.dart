import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/check_task.dart';
import '../../config/constants.dart';
import 'check_detail_screen.dart';
import 'check_report_screen.dart';
import 'check_plan_screen.dart';

class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadCheckTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isManager = appProvider.isManager;
    final currentUser = appProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('盘点管理'),
        actions: [
          // ★ v6.16: 店长可见"盘点规划"按钮
          if (isManager)
            IconButton(
              icon: const Icon(Icons.assignment_ind),
              tooltip: '盘点规划',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CheckPlanScreen()),
                );
                context.read<InventoryProvider>().loadCheckTasks();
              },
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CheckReportScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.checkTasks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          var tasks = provider.checkTasks;
          if (!isManager && currentUser.isNotEmpty) {
            // ★ v6.31: 员工也能看到已完成的盘点历史（不过滤 assignedTo），
            // 进行中的任务仍只显示分配给自己的
            final myName = appProvider.currentUsername.isNotEmpty ? appProvider.currentUsername : currentUser;
            tasks = tasks.where((t) =>
                t.status == CheckTaskStatus.completed ||
                t.assignedTo == null ||
                t.assignedTo == myName
            ).toList();
          }

          final activeTasks = tasks.where((t) => t.status != CheckTaskStatus.completed).toList();
          final historyTasks = tasks.where((t) => t.status == CheckTaskStatus.completed).toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ★ v6.29: 只有店长才能看到"新建盘点任务"按钮
              if (isManager) _buildNewTaskCard(),
              // ★ v6.16: 未盘点提醒
              if (activeTasks.any((t) => t.assignedTo == appProvider.currentUsername)) ...[
                const SizedBox(height: 8),
                _buildReminderBanner(activeTasks.where((t) => t.assignedTo == appProvider.currentUsername).toList()),
              ],
              const SizedBox(height: 16),
              const Text('进行中/待盘点', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (activeTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('暂无进行中的任务', style: TextStyle(color: Colors.grey))),
                )
              else
                ...activeTasks.map((t) => _buildDismissibleTaskCard(t, false)),
              const SizedBox(height: 16),
              const Text('盘点历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (historyTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('暂无历史记录', style: TextStyle(color: Colors.grey))),
                )
              else
                ...historyTasks.map((t) => _buildDismissibleTaskCard(t, true)),
            ],
          );
        },
      ),
    );
  }

  /// ★ v6.16: 未盘点提醒横幅
  Widget _buildReminderBanner(List<CheckTask> myTasks) {
    final total = myTasks.fold<int>(0, (s, t) => s + t.totalItems);
    final checked = myTasks.fold<int>(0, (s, t) => s + t.checkedItems);
    if (total == 0) return const SizedBox.shrink();
    final remaining = total - checked;
    if (remaining <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '你还有 $remaining 件商品未盘点，共 ${myTasks.length} 个任务未完成',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewTaskCard() {
    return Card(
      color: AppConstants.primaryColor.withOpacity(0.05),
      child: InkWell(
        onTap: _createNewTask,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: AppConstants.primaryColor, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '新建盘点任务',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '创建新的库存盘点任务',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// ★ v6.17: 可滑动删除 + 长按编辑
  Widget _buildDismissibleTaskCard(CheckTask task, bool isHistory) {
    // 已完成的历史记录不可编辑删除
    if (isHistory) return _buildTaskCard(task);

    return Dismissible(
      key: Key('check_${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: Text('删除 "${task.title}"？关联的盘点明细也会被删除。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        if (task.id != null) {
          await context.read<InventoryProvider>().deleteCheckTask(task.id!);
        }
      },
      child: GestureDetector(
        onLongPress: () => _editTask(task),
        child: _buildTaskCard(task),
      ),
    );
  }

  /// ★ v6.17: 编辑盘点任务标题
  void _editTask(CheckTask task) {
    final controller = TextEditingController(text: task.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '任务名称'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete, color: Colors.red, size: 18),
              label: const Text('删除此任务', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('确认删除'),
                    content: Text('确定删除 "${task.title}"？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true && task.id != null) {
                  await context.read<InventoryProvider>().deleteCheckTask(task.id!);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              final updated = task.copyWith(title: controller.text.trim());
              await context.read<InventoryProvider>().updateCheckTask(updated);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(CheckTask task) {
    // ★ v6.16: 解析货架信息用于显示
    final shelfCodes = task.shelfFilter?.split(',').where((s) => s.trim().isNotEmpty).toList() ?? [];
    final shelfLabel = shelfCodes.isNotEmpty ? '货架: ${shelfCodes.join(', ')}' : null;
    final assignedLabel = task.assignedTo != null ? '分配给: ${task.assignedTo}' : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: task.status.color.withOpacity(0.2),
          child: Icon(Icons.fact_check, color: task.status.color, size: 20),
        ),
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('操作人: ${task.operatorName}'),
            if (shelfLabel != null) Text(shelfLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (assignedLabel != null) Text(assignedLabel, style: const TextStyle(fontSize: 12, color: Colors.indigo)),
            if (task.status == CheckTaskStatus.inProgress || task.status == CheckTaskStatus.completed)
              Column(children: [
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: Colors.grey.shade200,
                  color: AppConstants.primaryColor,
                  minHeight: 4,
                ),
              ]),
          ],
        ),
        trailing: Chip(
          label: Text(task.status.displayName, style: TextStyle(fontSize: 11, color: task.status.color)),
          backgroundColor: task.status.color.withOpacity(0.1),
          side: BorderSide.none,
          padding: EdgeInsets.zero,
        ),
        onTap: () => _openTaskDetail(task),
      ),
    );
  }

  void _createNewTask() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建盘点任务'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: '任务名称',
            hintText: '例如: 2024年5月月度盘点',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isEmpty) return;
              final appProvider = context.read<AppProvider>();
              final task = CheckTask(
                title: titleController.text,
                operatorName: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : 'admin',
                assignedTo: appProvider.currentUser.isNotEmpty ? appProvider.currentUser : null,
              );
              await context.read<InventoryProvider>().createCheckTask(task);
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _openTaskDetail(CheckTask task) {
    if (task.status == CheckTaskStatus.completed) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckReportScreen(initialTask: task),
        ),
      ).then((_) {
        // Refresh task list when returning
        context.read<InventoryProvider>().loadCheckTasks();
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckDetailScreen(task: task),
        ),
      ).then((_) {
        // Refresh task list when returning
        context.read<InventoryProvider>().loadCheckTasks();
      });
    }
  }
}
