import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../models/shelf.dart';
import '../../services/database_service.dart';

class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadShelves();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('货架管理'),
      ),
      body: _buildShelfList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editShelfDialog(),
        icon: const Icon(Icons.add),
        label: const Text('新增货架'),
      ),
    );
  }

  Widget _buildShelfList() {
    return Consumer<InventoryProvider>(
      builder: (context, provider, child) {
        final shelves = provider.shelves;

        if (shelves.isEmpty) {
          return const Center(child: Text('暂无货架数据，点击右下角 + 新增'));
        }

        final zoneMap = <String, List<Shelf>>{};
        for (final shelf in shelves) {
          zoneMap.putIfAbsent(shelf.zone, () => []).add(shelf);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: zoneMap.length,
          itemBuilder: (context, index) {
            final zone = zoneMap.keys.elementAt(index);
            final zoneShelves = zoneMap[zone]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(zone, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text(
                            '${zoneShelves.length}个货架',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                      tooltip: '重命名区域',
                      onPressed: () => _renameZoneDialog(zone, provider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      tooltip: '删除区域',
                      onPressed: () => _deleteZoneConfirm(zone, provider),
                    ),
                  ],
                ),
                subtitle: null,
                leading: const Icon(Icons.location_on, color: Colors.indigo),
                children: [
                  ...zoneShelves.map((shelf) => _buildShelfTile(shelf, provider)),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _editShelfDialog(zone: zone),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('在 $zone 新增货架'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo,
                          side: BorderSide(color: Colors.indigo.shade200),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShelfTile(Shelf shelf, InventoryProvider provider) {
    return Dismissible(
      key: Key('shelf_${shelf.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定删除货架「${shelf.code} - ${shelf.name}」？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => provider.deleteShelf(shelf.id!),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        dense: true,
        title: Text('${shelf.code} - ${shelf.name}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
              onPressed: () => _editShelfDialog(shelf: shelf),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              tooltip: '删除货架',
              onPressed: () => _deleteShelfConfirm(shelf, provider),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
        onTap: () => _navigateToShelfProducts(shelf),
      ),
    );
  }

  void _renameZoneDialog(String oldZone, InventoryProvider provider) {
    final controller = TextEditingController(text: oldZone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名区域'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新区域名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final newZone = controller.text.trim();
              if (newZone.isNotEmpty && newZone != oldZone) {
                provider.batchRenameZone(oldZone, newZone);
              }
              Navigator.pop(ctx);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _deleteZoneConfirm(String zone, InventoryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除[$zone]及该区所有货架？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              provider.deleteZone(zone);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _deleteShelfConfirm(Shelf shelf, InventoryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除货架「${shelf.code} - ${shelf.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              provider.deleteShelf(shelf.id!);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _navigateToShelfProducts(Shelf shelf) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ShelfProductsPage(shelf: shelf),
      ),
    );
  }

  void _editShelfDialog({Shelf? shelf, String? zone}) {
    final isEdit = shelf != null;
    final codeController = TextEditingController(text: shelf?.code ?? '');
    final nameController = TextEditingController(text: shelf?.name ?? '');
    final prefilledZone = shelf?.zone ?? zone;
    final zoneController = TextEditingController(text: prefilledZone ?? '');

    final provider = context.read<InventoryProvider>();
    final existingZones = provider.shelves.map((s) => s.zone).toSet().toList()..sort();
    String? selectedZone = shelf?.zone;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑货架' : '新增货架'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: '货架编号 *', hintText: '例如: S01'),
                enabled: !isEdit,
              ),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '货架名称 *', hintText: '例如: 饮料主货架')),
              const SizedBox(height: 8),
              if (existingZones.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: selectedZone != null && existingZones.contains(selectedZone) ? selectedZone : null,
                  decoration: const InputDecoration(labelText: '所属区域 *', border: OutlineInputBorder()),
                  hint: const Text('选择已有区域'),
                  items: [
                    ...existingZones.map((z) => DropdownMenuItem(value: z, child: Text(z))),
                    const DropdownMenuItem(value: '__new__', child: Text('+ 新建区域', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600))),
                  ],
                  onChanged: (v) {
                    if (v == '__new__') {
                      setDialogState(() {
                        selectedZone = null;
                        zoneController.clear();
                      });
                    } else {
                      setDialogState(() {
                        selectedZone = v;
                        zoneController.text = v ?? '';
                      });
                    }
                  },
                ),
              if (selectedZone == null || selectedZone == '__new__' || existingZones.isEmpty)
                TextField(
                  controller: zoneController,
                  decoration: const InputDecoration(labelText: '新区域名称 *', hintText: '例如: A区'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final zoneVal = selectedZone != null && selectedZone != '__new__'
                    ? selectedZone!
                    : zoneController.text.trim();
                if (codeController.text.isEmpty || nameController.text.isEmpty || zoneVal.isEmpty) return;
                if (isEdit) {
                  await provider.updateShelf(shelf!.copyWith(name: nameController.text, zone: zoneVal));
                } else {
                  await provider.addShelf(Shelf(code: codeController.text, name: nameController.text, zone: zoneVal));
                }
                Navigator.pop(ctx);
              },
              child: Text(isEdit ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfProductsPage extends StatelessWidget {
  final Shelf shelf;
  const _ShelfProductsPage({required this.shelf});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${shelf.code} - ${shelf.name}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.instance.getInventoryWithProduct(shelfLocation: shelf.code),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data!;
          if (products.isEmpty) {
            return const Center(child: Text('该货架暂无商品'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              final qty = p['current_quantity'] ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(p['name_cn'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('条码: ${p['barcode'] ?? ''}'),
                      if (p['category'] != null) Text('分类: ${p['category']}'),
                    ],
                  ),
                  trailing: Text(
                    '库存: $qty',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: qty > 0 ? Colors.green : Colors.red),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
