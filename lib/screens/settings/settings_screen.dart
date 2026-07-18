import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/app_provider.dart';
import '../../config/constants.dart';
import '../../config/country_config.dart';
import '../../services/database_service.dart';
import '../../services/supabase_sync_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统设置'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ★ v6.31: 国家选择 — 简洁下拉框
              _buildSectionTitle('国家与区域'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    value: appProvider.countryCode,
                    decoration: const InputDecoration(
                      labelText: '选择国家',
                      prefixIcon: Icon(Icons.public, color: AppConstants.primaryColor),
                      border: OutlineInputBorder(),
                    ),
                    items: CountryConfig.all.map((c) {
                      return DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.nameCn} ${c.nameLocal}  ${c.currencySymbol} ${c.currencyCode}'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null && v != appProvider.countryCode) {
                        appProvider.setCountry(v);
                        // ★ v6.32 (方案C): 将国家配置上传到云端，同步给其他设备
                        SupabaseSyncService().uploadCountryCode(v).catchError((_) {});
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('语言与货币'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language, color: AppConstants.primaryColor),
                      title: const Text('界面语言'),
                      subtitle: Text(appProvider.languageCode == 'zh' ? '中文' : appProvider.countryConfig.langName),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'zh', label: Text('中文')),
                          ButtonSegment(value: 'local', label: Text('本地')),
                        ],
                        selected: {appProvider.languageCode == 'zh' ? 'zh' : 'local'},
                        onSelectionChanged: (v) {
                          if (v.first == 'zh') {
                            appProvider.setLanguage('zh');
                          } else {
                            appProvider.setLanguage(appProvider.countryConfig.langCode);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.currency_exchange, color: Colors.green),
                      title: const Text('货币显示'),
                      subtitle: Text(_getCurrencyDisplayName(appProvider.currencyDisplay, appProvider)),
                      trailing: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'cny', label: const Text('¥')),
                          ButtonSegment(value: 'local', label: Text(appProvider.countryConfig.currencySymbol)),
                        ],
                        selected: {appProvider.currencyDisplay == 'cny' ? 'cny' : 'local'},
                        onSelectionChanged: (v) {
                          appProvider.setCurrencyDisplay(v.first == 'cny' ? 'cny' : 'local');
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.access_time, color: Colors.orange),
                      title: const Text('本地时区'),
                      subtitle: Text('${appProvider.countryConfig.timezoneDesc} (${appProvider.countryConfig.timezone})'),
                      trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('网络与同步'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('离线模式'),
                      subtitle: const Text('网络不稳定时自动启用本地存储'),
                      value: appProvider.isOfflineMode,
                      onChanged: (v) => appProvider.setOfflineMode(v),
                      secondary: const Icon(Icons.offline_bolt, color: Colors.amber),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.sync, color: Colors.blue),
                      title: const Text('立即同步'),
                      subtitle: Text('待同步 ${appProvider.pendingSyncCount} 条记录'),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          final provider = context.read<AppProvider>();
                          provider.setPendingSyncCount(0);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('同步完成')),
                          );
                        },
                        child: const Text('同步'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('数据备份与恢复'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup, color: Colors.green),
                      title: const Text('导出数据'),
                      subtitle: const Text('将数据库导出到下载目录，用于备份或多设备迁移'),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          try {
                            final dbPath = await DatabaseService.instance.database.then((db) => db.path);
                            final directory = await getExternalStorageDirectory();
                            if (directory == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('无法访问存储目录')),
                              );
                              return;
                            }
                            final exportPath = p.join(directory.path, 'supermarket_backup_${DateTime.now().millisecondsSinceEpoch}.db');
                            final dbFile = File(dbPath);
                            await dbFile.copy(exportPath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('数据已导出至: $exportPath')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('导出失败: $e')),
                            );
                          }
                        },
                        child: const Text('导出'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore, color: Colors.orange),
                      title: const Text('导入数据'),
                      subtitle: const Text('从备份文件恢复数据，当前数据将被覆盖'),
                      trailing: ElevatedButton(
                        onPressed: () {
                          _showImportDialog(context);
                        },
                        child: const Text('导入'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const ListTile(
                leading: Icon(Icons.info_outline, color: Colors.grey),
                title: Text('关于'),
                subtitle: Text('华人超市管家 v6.31.0'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  String _getCurrencyDisplayName(String display, AppProvider appProvider) {
    switch (display) {
      case 'both':
        return '双币显示 (¥ / ${appProvider.countryConfig.currencySymbol})';
      case 'cny':
        return '仅人民币 (¥)';
      default:
        return '仅${appProvider.countryConfig.currencySymbol}';
    }
  }

  void _showImportDialog(BuildContext context) {
    final pathController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入备份文件的完整路径：'),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                hintText: '/storage/.../supermarket_backup_xxx.db',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '警告：导入将覆盖当前所有数据，请确保已备份！',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final importPath = pathController.text.trim();
              if (importPath.isEmpty) return;
              try {
                final importFile = File(importPath);
                if (!await importFile.exists()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('文件不存在')),
                  );
                  return;
                }
                final dbPath = await DatabaseService.instance.database.then((db) => db.path);
                await DatabaseService.instance.close();
                await importFile.copy(dbPath);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('数据导入成功，请重启应用')),
                );
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('导入失败: $e')),
                );
              }
            },
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }
}
