import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/database_service.dart';
import '../models/product.dart';
import '../models/inventory.dart';
import '../models/stock_record.dart';
import '../models/check_task.dart';
import '../models/user.dart' as local_user;

/// Supabase 同步结果
class SupabaseSyncResult {
  final bool success;
  final int uploadedStockRecords;
  final int uploadedCheckTasks;
  final int downloadedProducts;
  final int syncedStockCount;
  final int downloadedStockRecords;
  final int downloadedChecks;
  final String message;

  SupabaseSyncResult({
    required this.success,
    this.uploadedStockRecords = 0,
    this.uploadedCheckTasks = 0,
    this.downloadedProducts = 0,
    this.syncedStockCount = 0,
    this.downloadedStockRecords = 0,
    this.downloadedChecks = 0,
    required this.message,
  });
}

/// Supabase 云端同步服务（v6.2 → v6.10 持续迭代，修复跨设备同步失效）
///
/// ★ v6.2 相对 v6.1 的核心修复（解决"同一个超市不同手机同步不了"）：
///   1. device_id 防御性降级：上传/查重时若云端表无 device_id 列（migration 未执行），
///      自动回退到不带 device_id，保证上传不会因 400 错误而全部失败。
///   2. downloadProducts 不再用云端 stock 初始化本地库存（治翻倍根因）：
///      新商品本地库存=0，由 downloadStockRecords 应用历史流水得到正确库存。
///   3. downloadStockRecords 改用 synced_cloud_records 表做幂等查重（按云端记录 id），
///      不再用"业务字段+时间窗口"去重，彻底避免误杀跨设备流水。
///   4. downloadStockRecords：localProduct==null 时不推进 lastSyncTime（治漏数据）。
///   5. downloadStockRecords：插入本地时显式 is_synced=1（治 toMap 漏字段导致翻倍）。
///   6. lastSyncTime 推进时减去 60 秒安全裕量，容忍跨设备时钟偏差。
///   7. fullSync 流程调整：先下载商品、再下载流水（确保 localProduct 存在再应用流水）。
///
/// 同步策略：
///   - 每次入库/出库后，即时通过 HTTP PATCH 更新云端 products.stock（幂等覆盖）
///   - 30 秒轮询 fullSync()，双向同步出入库流水、盘点任务、用户数据
///   - 本地 SQLite 是主数据源，云表是交换层
///   - device_id 仅用于本地标识；云端是否有 device_id 列均可工作
class SupabaseSyncService {
  final DatabaseService _db = DatabaseService.instance;

  /// ★ v6.3: 当前店铺ID（动态，支持多店区分）
  /// 默认 'main' 兼容老数据；通过 setStoreId() 切换
  /// 初始化时从 SharedPreferences 加载
  String _storeId = 'main';
  String get storeId => _storeId;

  /// SharedPreferences keys
  static const String _deviceIdKey = 'sync_device_id';
  static const String _lastStockSyncKey = 'last_stock_sync_time';
  static const String _lastCheckSyncKey = 'last_check_sync_time';
  static const String _storeIdKey = 'store_id';  // ★ v6.3
  static const String _appVersionKey = 'app_sync_version'; // ★ v6.5 版本检测

  /// 缓存的设备ID
  String? _deviceId;

  /// device_id 列是否可用的缓存（避免每次请求都试探）
  /// null=未知, true=可用, false=不可用
  bool? _deviceIdColumnAvailable;

  /// ★ v6.3: 构造时从 prefs 加载 storeId
  SupabaseSyncService() {
    _loadStoreId();
    _checkVersionAndForceResync();
  }

  /// ★ v6.31 fix: 每次同步前从 prefs 重新读取 store_id，确保与 AppProvider 一致
  Future<void> _ensureStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storeIdKey);
    if (stored != null && stored.isNotEmpty) {
      _storeId = stored;
    }
    // ★ v6.32: 如果 Supabase session 丢了，用保存的 refreshToken 自动恢复
    await _restoreSessionIfNeeded();
  }

  /// ★ v6.32: 用 SharedPreferences 中保存的 refreshToken 恢复 Supabase session
  Future<void> _restoreSessionIfNeeded() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession != null) return; // 已有 session，不需要恢复
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('supabase_refresh_token');
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await client.auth.refreshSession(refreshToken);
        debugPrint('[Sync] _restoreSessionIfNeeded: session 已自动恢复');
      }
    } catch (e) {
      debugPrint('[Sync] _restoreSessionIfNeeded failed: $e');
    }
  }

  Future<void> _loadStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    _storeId = prefs.getString(_storeIdKey) ?? 'main';
  }

  /// ★ v6.5: 检测 App 版本变化，自动强制全量重同步
  /// 解决覆盖安装后 lastSyncTime 残留导致"完全不同步"的问题
  Future<void> _checkVersionAndForceResync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const currentVersion = 'v6.30';
      final savedVersion = prefs.getString(_appVersionKey);

      if (savedVersion != currentVersion) {
        debugPrint('[Sync] Version changed: $savedVersion -> $currentVersion, forcing full resync');
        await forceFullResync();
        await prefs.setString(_appVersionKey, currentVersion);
      }
    } catch (e) {
      debugPrint('[Sync] _checkVersionAndForceResync error: $e');
    }
  }

  /// ★ v6.13→v6.27: 版本升级时只清除同步时间戳，让全量拉取重新执行，但**不删除本地数据**
  /// 修复：删除 is_synced=1 记录 + 重置库存为 0 → downloadStockRecords 跳过自己设备的记录
  /// → 本设备上传的记录永远无法从云端恢复 → 库存永远为 0
  Future<void> forceFullResync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastStockSyncKey);
      await prefs.remove(_lastCheckSyncKey);
      debugPrint('[Sync] Cleared lastSyncTime for full resync');

      // ★ v6.27: 不再删除 stock_records / 清空库存 / 清 synced_cloud_records
      // 仅通过清除时间戳使下次 fullSync 全量拉取云端数据
      // synced_cloud_records 的幂等查重会防止重复；本地已有的正确数据不会被破坏

      // 重置 device_id 列可用性缓存（重新探测）
      _deviceIdColumnAvailable = null;
    } catch (e) {
      debugPrint('[Sync] forceFullResync error: $e');
    }
  }

  /// ★ v6.3: 切换当前超市ID（注册新超市或加入已有超市时调用）
  Future<void> setStoreId(String id) async {
    if (id.isEmpty) return;
    _storeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, id);
    // 切换超市后重置同步时间戳，强制全量拉取新超市的数据
    await prefs.remove(_lastStockSyncKey);
    await prefs.remove(_lastCheckSyncKey);
  }

  /// HTTP headers 通用部分
  /// ★ v6.31: 优先使用已登录用户的 JWT token，未登录时回退到 anonKey
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${_authToken ?? SupabaseConfig.anonKey}',
        'Prefer': 'return=minimal',
      };

  /// 需要返回数据的 HTTP headers
  Map<String, String> get _headersWithReturn => {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${_authToken ?? SupabaseConfig.anonKey}',
        'Prefer': 'return=representation',
      };

  /// ★ v6.31: 获取当前 Supabase Auth 用户的 access token
  String? get _authToken {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (e) {
      return null;
    }
  }

  // ==================== 设备ID管理（仅本地使用） ====================

  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);

    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }

    return _deviceId!;
  }

  // ==================== 同步时间戳管理 ====================

  Future<DateTime?> _getLastStockSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastStockSyncKey);
    if (timeStr == null || timeStr.isEmpty) return null;
    return DateTime.tryParse(timeStr);
  }

  Future<void> _setLastStockSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastStockSyncKey, time.toUtc().toIso8601String());
  }

  Future<DateTime?> _getLastCheckSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastCheckSyncKey);
    if (timeStr == null || timeStr.isEmpty) return null;
    return DateTime.tryParse(timeStr);
  }

  Future<void> _setLastCheckSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckSyncKey, time.toUtc().toIso8601String());
  }

  // ==================== ★ v6.2 新增：device_id 防御性处理 ====================

  /// 防御性 POST：先尝试带 device_id，若返回 400（列不存在/类型不匹配）则标记列不可用并回退重试
  ///
  /// 解决根因①：上一版假设"云端会忽略不存在的 device_id 字段"是错的，
  /// PostgREST 对未知列返回 400，导致所有上传失败、跨设备同步完全跑不通。
  /// ★ v6.31 fix: 同时兼容 device_id 列类型不匹配（如整数列收到 UUID 字符串），
  /// 只要错误信息包含 device_id 就回退到不带 device_id 上传。
  Future<http.Response> _defensivePost(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('${SupabaseConfig.restBaseUrl}$path');
    final h = headers ?? _headers;
    final deviceId = await getDeviceId();
    final bodyWithDevice = Map<String, dynamic>.from(body);
    if (!bodyWithDevice.containsKey('device_id')) {
      bodyWithDevice['device_id'] = deviceId;
    }

    // 已知列不可用 -> 直接走不带 device_id 的路径
    if (_deviceIdColumnAvailable == false) {
      final fallback = Map<String, dynamic>.from(bodyWithDevice)
        ..remove('device_id');
      return http
          .post(uri, headers: h, body: jsonEncode(fallback))
          .timeout(timeout);
    }

    // 未知或可用 -> 先尝试带 device_id
    final res = await http
        .post(uri, headers: h, body: jsonEncode(bodyWithDevice))
        .timeout(timeout);

    // ★ v6.31 fix: 任何包含 device_id 的 400 错误都回退（列不存在或类型不匹配）
    if (res.statusCode == 400 && res.body.contains('device_id')) {
      debugPrint('[Sync] _defensivePost: device_id error -> fallback without device_id. body=${res.body}');
      _deviceIdColumnAvailable = false;
      final fallback = Map<String, dynamic>.from(bodyWithDevice)
        ..remove('device_id');
      return http
          .post(uri, headers: h, body: jsonEncode(fallback))
          .timeout(timeout);
    }

    if (res.statusCode == 201 || res.statusCode == 200) {
      _deviceIdColumnAvailable = true;
    }
    return res;
  }

  /// 防御性 dupCheck：查询云端是否已有该记录（按 device_id+local_id 或仅 local_id）
  /// 返回 true 表示已存在（应跳过），false 表示不存在（应上传）
  ///
  /// ★ v6.4 修复根因①：
  ///   当 device_id 列不可用时，直接返回 false（不阻止上传）。
  ///   原来用 store_id+local_id 查重，但 local_id 是本地 SQLite 自增ID，
  ///   不同设备会有相同的 local_id（如都是 5），导致跨设备上传被误判为重复而跳过。
  ///   下载端的 synced_cloud_records + 业务字段去重会处理真正的重复记录。
  Future<bool> _defensiveDupCheck(String table, int localId) async {
    final deviceId = await getDeviceId();

    // 已知 device_id 列不可用 → 不查重，直接放行上传
    // ★ v6.4 修复：原来用 store_id+local_id 查重会导致跨设备碰撞
    if (_deviceIdColumnAvailable == false) {
      return false; // 不阻止上传，由下载端去重
    }

    // 未知或可用 → 先尝试带 device_id
    final uri = Uri.parse(
      '${SupabaseConfig.restBaseUrl}/$table'
      '?store_id=eq.$_storeId'
      '&device_id=eq.$deviceId'
      '&local_id=eq.$localId'
      '&select=id'
      '&limit=1',
    );
    try {
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode == 200) {
        _deviceIdColumnAvailable = true;
        final List<dynamic> existing = jsonDecode(res.body);
        return existing.isNotEmpty;
      }
      if (res.statusCode == 400 &&
          res.body.contains('device_id') &&
          res.body.toLowerCase().contains('column')) {
        // 列不存在，标记为不可用，放行上传
        _deviceIdColumnAvailable = false;
        return false; // ★ v6.4: 不再递归调用，直接放行
      }
    } catch (e) {
      debugPrint('[Sync] _defensiveDupCheck error: $e');
    }
    return false;
  }

  // ==================== 辅助：查询本地商品 product_id ====================

  Future<int> _getProductIdForBarcode(String barcode) async {
    final localProduct = await _db.getProductByBarcode(barcode);
    if (localProduct != null && localProduct.id != null) {
      return localProduct.id!;
    }
    return 0;
  }

  /// 将本地某商品的当前库存幂等覆盖到云端 products.stock
  Future<void> _syncLocalStockToCloud(String barcode) async {
    try {
      final localProduct = await _db.getProductByBarcode(barcode);
      if (localProduct == null) return;
      final inv = await _db.getInventoryByProductId(localProduct.id!);
      final localStock = inv?.currentQuantity ?? 0;

      final lookupUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/products?store_id=eq.${_storeId}&barcode=eq.${Uri.encodeComponent(barcode)}&select=id',
      );
      final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (lookupRes.statusCode != 200) return;
      final List<dynamic> products = jsonDecode(lookupRes.body);
      if (products.isEmpty) return;
      final cloudId = products.first['id'] as String;

      await http.patch(
        Uri.parse('${SupabaseConfig.restBaseUrl}/products?id=eq.${Uri.encodeComponent(cloudId)}'),
        headers: _headers,
        body: jsonEncode({
          'stock': localStock,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      // 回写失败不影响主流程
    }
  }

  // ==================== 盘点任务/明细跨设备同步辅助方法 ====================

  /// 查找云端盘点任务：先按 device_id+local_id 精确查，再按 title+operator+store_id 兜底
  /// 返回 {'id': cloudTaskId, 'status': cloudStatus} 或 null
  /// 解决"盘点规划"生成的任务在不同设备上 local_id 不同，导致重复建云端任务、明细丢失的问题
  Future<Map<String, String>?> _lookupCloudTask(
    int localTaskId,
    String title,
    String operatorName, {
    String? status,
  }) async {
    final deviceId = await getDeviceId();

    // 1) 精确：device_id + local_id（本设备上传过的任务）
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/check_tasks_cloud'
        '?store_id=eq.$_storeId'
        '&device_id=eq.$deviceId'
        '&local_id=eq.$localTaskId'
        '&select=id,status'
        '&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode == 200) {
        final List<dynamic> existing = jsonDecode(res.body);
        if (existing.isNotEmpty) {
          return {
            'id': existing.first['id']?.toString() ?? '',
            'status': (existing.first['status'] as String?) ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('[Sync] _lookupCloudTask by device_id error: $e');
    }

    // 2) 兜底：title + operator_name + store_id（跨设备的规划任务）
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/check_tasks_cloud'
        '?store_id=eq.$_storeId'
        '&title=eq.${Uri.encodeComponent(title)}'
        '&operator_name=eq.${Uri.encodeComponent(operatorName)}'
        '${status != null ? '&status=eq.$status' : ''}'
        '&select=id,status'
        '&order=created_at.desc'
        '&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode == 200) {
        final List<dynamic> existing = jsonDecode(res.body);
        if (existing.isNotEmpty) {
          return {
            'id': existing.first['id']?.toString() ?? '',
            'status': (existing.first['status'] as String?) ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('[Sync] _lookupCloudTask by title error: $e');
    }

    return null;
  }

  /// 查询云端某盘点任务是否已有明细
  Future<bool> _hasCloudDetails(String cloudTaskId) async {
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/check_details_cloud'
        '?store_id=eq.$_storeId'
        '&task_id=eq.$cloudTaskId'
        '&select=id'
        '&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode == 200) {
        final List<dynamic> existing = jsonDecode(res.body);
        return existing.isNotEmpty;
      }
    } catch (e) {
      debugPrint('[Sync] _hasCloudDetails error: $e');
    }
    return false;
  }

  /// 入库后调用：将本地库存数量同步到云端
  ///
  /// ★ v6.2 幂等性保障：
  ///   1. 防御性 dupCheck（device_id 列不存在时自动回退）
  ///   2. 云端 products.stock 采用幂等覆盖（PATCH = 本地当前库存）
  ///   3. 写 stock_records_cloud 用 _defensivePost（device_id 列不存在时回退）
  Future<bool> syncStockIn(String barcode, int quantity,
      {int? localRecordId,
      String operatorName = '云端同步',
      double priceCny = 0.0,
      double priceUzs = 0.0,
      String? note,
      String? supplier,
      String? expiryDate,
      String? productionDate,
      String? batchNumber,
      String? createdAt}) async {
    try {
      await _ensureStoreId();  // ★ v6.31 fix
      // ★ 0) 幂等检查
      if (localRecordId != null) {
        final exists = await _defensiveDupCheck('stock_records_cloud', localRecordId);
        if (exists) {
          await _db.markRecordSynced(localRecordId);
          return true;
        }
      }

      // ★ 1) 读本地当前库存（用于幂等覆盖云端 stock）
      final localProduct = await _db.getProductByBarcode(barcode);
      int? localStock;
      if (localProduct != null) {
        final inv = await _db.getInventoryByProductId(localProduct.id!);
        localStock = inv?.currentQuantity ?? 0;
      }

      // ★ 2) 更新云端 products.stock（幂等覆盖）
      // ★ v6.31 fix: products 表写入失败不中断 stock_records_cloud 上传
      // 原因是 Supabase RLS 可能禁止匿名 INSERT products，但允许 INSERT stock_records_cloud
      try {
        final lookupUri = Uri.parse(
          '${SupabaseConfig.restBaseUrl}/products?store_id=eq.${_storeId}&barcode=eq.${Uri.encodeComponent(barcode)}&select=id,stock,name',
        );
        final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
          const Duration(seconds: 10),
        );

        if (lookupRes.statusCode == 200) {
          final List<dynamic> products = jsonDecode(lookupRes.body);

          if (products.isNotEmpty) {
            final cloud = products.first;
            final cloudId = cloud['id'] as String;
            final cloudName = (cloud['name'] as String?) ?? '';

            if (localStock != null || (localProduct != null && (localProduct.priceCny > 0 || localProduct.priceUzs > 0 || localProduct.nameCn.isNotEmpty))) {
              final patchBody = <String, dynamic>{
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              };
              if (localStock != null) {
                patchBody['stock'] = localStock;
              }
              // ★ v6.31 fix: 同步价格到云端
              if (localProduct != null) {
                if (localProduct.priceCny > 0) {
                  patchBody['price_cny'] = localProduct.priceCny;
                }
                if (localProduct.priceUzs > 0) {
                  patchBody['price'] = localProduct.priceUzs;
                }
                if (localProduct.costPriceCny > 0) {
                  patchBody['cost_price'] = localProduct.costPriceCny;
                }
                // 始终补传本地名称
                if (localProduct.nameCn.isNotEmpty) {
                  patchBody['name'] = localProduct.nameCn;
                }
                // 补传分类名（替代无法使用的 category_id UUID）
                if (localProduct.category.isNotEmpty && localProduct.category != '其他') {
                  patchBody['category_name'] = localProduct.category;
                }
              }
              await http.patch(
                Uri.parse('${SupabaseConfig.restBaseUrl}/products?id=eq.${Uri.encodeComponent(cloudId)}'),
                headers: _headers,
                body: jsonEncode(patchBody),
              ).timeout(const Duration(seconds: 10)).then((res) {
                debugPrint('[Sync] syncStockIn PATCH barcode=$barcode status=${res.statusCode} stock=$localStock name=${localProduct?.nameCn}');
                if (res.statusCode != 200 && res.statusCode != 204) {
                  debugPrint('[Sync] syncStockIn PATCH FAILED body=${res.body}');
                }
              });
            }
          } else {
            // 云端没有该商品 -> 尝试创建
            if (localProduct != null) {
              final productBody = {
                'store_id': _storeId,
                'barcode': barcode,
                'name': localProduct.nameCn,
                'category_name': localProduct.category.isNotEmpty ? localProduct.category : '其他',
                'price': localProduct.priceUzs,
                'price_cny': localProduct.priceCny,
                'cost_price': localProduct.costPriceCny,
                'unit': localProduct.unit ?? '个',
                'stock': localStock ?? quantity,
                'min_stock': 10,
                'is_active': true,
              };
              // ★ v6.31 fix: 不传 category_id — 本地 category 是文本（如"食品"），
              // 但云端 category_id 是 UUID 类型，传非 UUID 字符串会导致 400 错误
              var createRes = await http.post(
                Uri.parse('${SupabaseConfig.restBaseUrl}/products'),
                headers: _headers,
                body: jsonEncode(productBody),
              ).timeout(const Duration(seconds: 10));
              debugPrint('[Sync] syncStockIn create product barcode=$barcode status=${createRes.statusCode} body=${createRes.body}');

              // ★ v6.31: POST 失败时重试一次（可能是短暂的网络或认证问题）
              if (createRes.statusCode != 201) {
                debugPrint('[Sync] syncStockIn create RETRY for $barcode');
                createRes = await http.post(
                  Uri.parse('${SupabaseConfig.restBaseUrl}/products'),
                  headers: _headers,
                  body: jsonEncode(productBody),
                ).timeout(const Duration(seconds: 10));
                debugPrint('[Sync] syncStockIn create retry status=${createRes.statusCode}');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Sync] syncStockIn products update skipped: $e');
      }

      // 3) 获取 product_id
      final productId = await _getProductIdForBarcode(barcode);

      // ★ 4) 写入 stock_records_cloud 流水（含 device_id 用于设备过滤去重）
      // ★ v6.11: 优先使用记录原始时间，兜底用 now
      final cloudCreatedAt = createdAt ?? DateTime.now().toUtc().toIso8601String();
      final syncDeviceId = await getDeviceId();
      final recordBody = {
        'store_id': _storeId,
        'local_id': localRecordId,
        'product_id': productId,
        'barcode': barcode,
        'type': 'inBound',
        'quantity': quantity,
        'price_cny': priceCny,
        'price_uzs': priceUzs,
        'operator_name': operatorName,
        'note': note,
        'device_id': syncDeviceId,
        'is_synced': 1,
        'created_at': cloudCreatedAt,
      };
      // supplier 字段云端表可能没有，单独防御性处理
      if (supplier != null && supplier.isNotEmpty) {
        recordBody['supplier'] = supplier;
      }
      // ★ v6.6 新增：批次字段（临期预警依赖）
      if (expiryDate != null && expiryDate.isNotEmpty) {
        recordBody['expiry_date'] = expiryDate;
      }
      if (productionDate != null && productionDate.isNotEmpty) {
        recordBody['production_date'] = productionDate;
      }
      if (batchNumber != null && batchNumber.isNotEmpty) {
        recordBody['batch_number'] = batchNumber;
      }

      final recordRes = await _defensivePost(
        '/stock_records_cloud',
        recordBody,
      ).timeout(const Duration(seconds: 10));
      debugPrint('[Sync] syncStockIn barcode=$barcode recordBody.expiry_date=${recordBody['expiry_date']} status=${recordRes.statusCode} body=${recordRes.body}');

      // ★ 防御性重试：去掉云端可能不存在的列
      // v6.8 扩展：expiry_date/production_date/batch_number/supplier 都可能不存在
      if (recordRes.statusCode == 400) {
        debugPrint('[Sync] syncStockIn barcode=$barcode retry without expiry_date/production_date/batch_number/supplier');
        final retryBody = Map<String, dynamic>.from(recordBody)
          ..remove('expiry_date')
          ..remove('production_date')
          ..remove('batch_number')
          ..remove('supplier');
        final retryRes = await _defensivePost(
          '/stock_records_cloud',
          retryBody,
        ).timeout(const Duration(seconds: 10));
        debugPrint('[Sync] syncStockIn barcode=$barcode retry status=${retryRes.statusCode} body=${retryRes.body}');
        final cloudOk = retryRes.statusCode == 201;
        if (cloudOk && localRecordId != null) {
          await _db.markRecordSynced(localRecordId);
        }
        return cloudOk;
      }

      final cloudOk = recordRes.statusCode == 201;

      if (cloudOk && localRecordId != null) {
        await _db.markRecordSynced(localRecordId);
      }

      return cloudOk;
    } catch (e) {
      debugPrint('[Sync] syncStockIn error: $e');
      return false;
    }
  }

  /// 出库后调用：将云端库存数量扣减（幂等覆盖）
  Future<bool> syncStockOut(String barcode, int quantity,
      {int? localRecordId,
      String operatorName = '云端同步',
      double priceCny = 0.0,
      double priceUzs = 0.0,
      double costPriceCny = 0.0,
      String? note,
      String? destination,
      String? outboundReason,
      String? expiryDate,
      String? productionDate,
      String? batchNumber,
      String? supplier,
      String? createdAt}) async {
    try {
      await _ensureStoreId();  // ★ v6.31 fix
      // ★ 0) 幂等检查
      if (localRecordId != null) {
        final exists = await _defensiveDupCheck('stock_records_cloud', localRecordId);
        if (exists) {
          await _db.markRecordSynced(localRecordId);
          return true;
        }
      }

      // ★ 1) 读本地当前库存
      final localProduct = await _db.getProductByBarcode(barcode);
      int? localStock;
      if (localProduct != null) {
        final inv = await _db.getInventoryByProductId(localProduct.id!);
        localStock = inv?.currentQuantity ?? 0;
      }

      // ★ 2) 更新云端 products.stock（幂等覆盖）
      // ★ v6.31 fix: products 表写入失败不中断 stock_records_cloud 上传
      try {
        final lookupUri = Uri.parse(
          '${SupabaseConfig.restBaseUrl}/products?store_id=eq.${_storeId}&barcode=eq.${Uri.encodeComponent(barcode)}&select=id,stock,name',
        );
        final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
          const Duration(seconds: 10),
        );

        if (lookupRes.statusCode == 200) {
          final List<dynamic> products = jsonDecode(lookupRes.body);
          if (products.isNotEmpty) {
            final cloud = products.first;
            final cloudId = cloud['id'] as String;

            if (localStock != null) {
              final clampedStock = localStock.clamp(0, 999999);
              await http.patch(
                Uri.parse('${SupabaseConfig.restBaseUrl}/products?id=eq.${Uri.encodeComponent(cloudId)}'),
                headers: _headers,
                body: jsonEncode({
                  'stock': clampedStock,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                }),
              ).timeout(const Duration(seconds: 10)).then((res) {
                debugPrint('[Sync] syncStockOut PATCH barcode=$barcode status=${res.statusCode} stock=$clampedStock');
                if (res.statusCode != 200 && res.statusCode != 204) {
                  debugPrint('[Sync] syncStockOut PATCH FAILED body=${res.body}');
                }
              });
            }
          }
        }
      } catch (e) {
        debugPrint('[Sync] syncStockOut products update skipped: $e');
      }

      // 3) 获取 product_id
      final productId = await _getProductIdForBarcode(barcode);

      // ★ 4) 写入 stock_records_cloud 流水（含 device_id 用于设备过滤去重）
      // ★ v6.11: 优先使用记录原始时间，兜底用 now
      final cloudCreatedAt = createdAt ?? DateTime.now().toUtc().toIso8601String();
      final syncDeviceId = await getDeviceId();
      final recordBody = {
        'store_id': _storeId,
        'local_id': localRecordId,
        'product_id': productId,
        'barcode': barcode,
        'type': 'outBound',
        'quantity': quantity,
        'price_cny': priceCny,
        'price_uzs': priceUzs,
        'cost_price_cny': costPriceCny > 0 ? costPriceCny : null,
        'operator_name': operatorName,
        'note': note,
        'device_id': syncDeviceId,
        'is_synced': 1,
        'created_at': cloudCreatedAt,
      };
      // 这两个字段云端表可能没有，单独防御性处理
      if (outboundReason != null && outboundReason.isNotEmpty) {
        recordBody['outbound_reason'] = outboundReason;
      }
      if (destination != null && destination.isNotEmpty) {
        recordBody['destination'] = destination;
      }
      // ★ v6.6 新增：批次字段（临期预警依赖）
      if (expiryDate != null && expiryDate.isNotEmpty) {
        recordBody['expiry_date'] = expiryDate;
      }
      if (productionDate != null && productionDate.isNotEmpty) {
        recordBody['production_date'] = productionDate;
      }
      if (batchNumber != null && batchNumber.isNotEmpty) {
        recordBody['batch_number'] = batchNumber;
      }
      if (supplier != null && supplier.isNotEmpty) {
        recordBody['supplier'] = supplier;
      }

      final recordRes = await _defensivePost(
        '/stock_records_cloud',
        recordBody,
      ).timeout(const Duration(seconds: 10));
      debugPrint('[Sync] syncStockOut barcode=$barcode recordBody.expiry_date=${recordBody['expiry_date']} status=${recordRes.statusCode} body=${recordRes.body}');

      // ★ v6.8：防御性重试，去掉云端可能不存在的所有可选列
      if (recordRes.statusCode == 400) {
        debugPrint('[Sync] syncStockOut barcode=$barcode retry without optional columns');
        final retryBody = Map<String, dynamic>.from(recordBody)
          ..remove('outbound_reason')
          ..remove('destination')
          ..remove('expiry_date')
          ..remove('production_date')
          ..remove('batch_number')
          ..remove('supplier');
        final retryRes = await _defensivePost(
          '/stock_records_cloud',
          retryBody,
        ).timeout(const Duration(seconds: 10));
        debugPrint('[Sync] syncStockOut barcode=$barcode retry status=${retryRes.statusCode} body=${retryRes.body}');
        final cloudOk = retryRes.statusCode == 201;
        if (cloudOk && localRecordId != null) {
          await _db.markRecordSynced(localRecordId);
        }
        return cloudOk;
      }

      final cloudOk = recordRes.statusCode == 201;

      if (cloudOk && localRecordId != null) {
        await _db.markRecordSynced(localRecordId);
      }

      return cloudOk;
    } catch (e) {
      debugPrint('[Sync] syncStockOut error: $e');
      return false;
    }
  }

  /// ★ v6.31: 单独同步商品价格到云端（上架/定价后调用）
  /// costPriceCny = 进价（人民币），sellPriceUzs = 售价（当地货币），sellPriceCny = 售价（人民币）
  Future<bool> syncProductPrice(String barcode, double costPriceCny, double sellPriceUzs, {double sellPriceCny = 0, String? categoryName}) async {
    try {
      await _ensureStoreId();
      final lookupUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/products?store_id=eq.$_storeId&barcode=eq.${Uri.encodeComponent(barcode)}&select=id',
      );
      final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
        const Duration(seconds: 10),
      );
      if (lookupRes.statusCode == 200) {
        final List<dynamic> products = jsonDecode(lookupRes.body);
        if (products.isNotEmpty) {
          final cloudId = products.first['id'] as String;
          final patchBody = <String, dynamic>{
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          if (costPriceCny > 0) patchBody['cost_price'] = costPriceCny;
          if (sellPriceUzs > 0) patchBody['price'] = sellPriceUzs;
          if (sellPriceCny > 0) patchBody['price_cny'] = sellPriceCny;
          if (categoryName != null && categoryName.isNotEmpty && categoryName != '其他') {
            patchBody['category_name'] = categoryName;
          }
          final patchRes = await http.patch(
            Uri.parse('${SupabaseConfig.restBaseUrl}/products?id=eq.${Uri.encodeComponent(cloudId)}'),
            headers: _headers,
            body: jsonEncode(patchBody),
          ).timeout(const Duration(seconds: 10));
          debugPrint('[Sync] syncProductPrice: $barcode costPriceCny=$costPriceCny sellPriceUzs=$sellPriceUzs sellPriceCny=$sellPriceCny status=${patchRes.statusCode}');
          return patchRes.statusCode == 200 || patchRes.statusCode == 204;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[Sync] syncProductPrice error: $e');
      return false;
    }
  }

  // ==================== 全量下载云端商品信息到本地 ====================

  /// 从 Supabase 拉取所有商品基础信息到本地
  ///
  /// ★ v6.31 策略：库存完全由 downloadStockRecords 应用历史流水驱动。
  /// 本方法只负责同步商品信息（名称、品类、价格等），不初始化本地库存。
  /// downloadStockRecords 首次全量拉取流水时通过 synced_cloud_records 幂等查重，
  /// 防止同一条流水被重复应用导致翻倍。
  Future<int> downloadProducts() async {
    final uri = Uri.parse(
      '${SupabaseConfig.restBaseUrl}/products?store_id=eq.${_storeId}&select=id,barcode,name,category_id,category_name,price,cost_price,price_cny,unit,stock,min_stock,is_active',
    );
    final response = await http.get(uri, headers: _headers).timeout(
      const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception('下载云端数据失败: HTTP ${response.statusCode}');
    }

    final List<dynamic> cloudProducts = jsonDecode(response.body);
    int count = 0;

    for (final cp in cloudProducts) {
      final barcode = cp['barcode'] as String? ?? '';
      if (barcode.isEmpty || barcode.startsWith('__')) continue; // 跳过特殊条码和空条码

      // ★ v6.31: name 为空时不跳过，用 barcode 兜底。避免 A 手机上传失败时 B 手机永远看不到该商品
      final cloudName = cp['name'] as String? ?? '';
      final name = cloudName.isNotEmpty ? cloudName : '商品($barcode)';

      final existing = await _db.getProductByBarcode(barcode);

      if (existing == null) {
        // 本地没有此商品 -> 插入本地（库存由流水驱动，不在此处初始化）
        await _db.insertProduct(Product(
          barcode: barcode,
          nameCn: name,
          category: cp['category_name'] as String? ?? cp['category_id'] as String? ?? '其他',
          priceCny: (cp['price_cny'] as num?)?.toDouble() ?? 0,
          priceUzs: (cp['price'] as num?)?.toDouble() ?? 0,
          unit: cp['unit'] as String? ?? '个',
        ));
        count++;
        } else {
        // ★ v6.31: 云端名称非空时，更新本地名称（覆盖占位/未命名商品）
        final localName = existing.nameCn;
        final isPlaceholder = localName.isEmpty || localName.startsWith('未命名商品') || localName.startsWith('商品(');
        if (isPlaceholder && cloudName.isNotEmpty && existing.id != null) {
          await _db.updateProductName(existing.id!, cloudName);
        } else if (localName != cloudName && cloudName.isNotEmpty && existing.id != null) {
          await _db.updateProductName(existing.id!, cloudName);
        }
        // ★ v6.32: 更新分类（从云端 category_name 覆盖本地 category）
        final cloudCategory = cp['category_name'] as String?;
        if (cloudCategory != null && cloudCategory.isNotEmpty &&
            cloudCategory != '其他' && existing.category != cloudCategory && existing.id != null) {
          await _db.updateProductCategory(existing.id!, cloudCategory);
        }
        // 从云端更新三个价格字段
        if (existing.id != null) {
          final db = await _db.database;
          final updates = <String, dynamic>{};
          final cloudPriceUzs = (cp['price'] as num?)?.toDouble() ?? 0;
          final cloudPriceCny = (cp['price_cny'] as num?)?.toDouble() ?? 0;
          if (cloudPriceUzs > 0 && existing.priceUzs != cloudPriceUzs) {
            // ★ v6.32 (方案C): 价格合理性保护
            // 如果云端当地货币=人民币（表明是历史错误数据），且本地已有不同价格，不覆盖
            final bool looksBad = cloudPriceCny > 0 && cloudPriceUzs == cloudPriceCny;
            if (!looksBad || existing.priceUzs == 0) {
              updates['price_uzs'] = cloudPriceUzs;
            } else {
              debugPrint('[Sync] downloadProducts: skip bad price_uzs=$cloudPriceUzs for $barcode '
                  '(local=${existing.priceUzs}, cny=$cloudPriceCny)');
            }
          }
          if (cloudPriceCny > 0 && existing.priceCny != cloudPriceCny) {
            updates['price_cny'] = cloudPriceCny;
          }
          // 进价单独更新（只增不减，避免泄露为0的情况）
          final cloudCostCny = (cp['cost_price'] as num?)?.toDouble() ?? 0;
          if (cloudCostCny > 0) {
            updates['cost_price_cny'] = cloudCostCny;
          }
          if (updates.isNotEmpty) {
            updates['updated_at'] = DateTime.now().toIso8601String();
            await db.update('products', updates, where: 'id = ?', whereArgs: [existing.id]);
          }
        }
        count++;
      }
    }

    return count;
  }

  // ==================== 出入库记录上传（含去重检查） ====================

  /// 上传所有 is_synced=0 的本地出入库记录到云端
  Future<int> uploadPendingStockRecords() async {
    final records = await _db.getUnsyncedRecords();
    if (records.isEmpty) return 0;

    int count = 0;

    for (final record in records) {
      try {
        final barcode = record['barcode'] as String;
        final type = record['type'] as String;
        final quantity = record['quantity'] as int;
        final recordId = record['id'] as int;
        final opName = (record['operator_name'] as String?) ?? '云端同步';
        final priceCny = (record['price_cny'] as num?)?.toDouble() ?? 0.0;
        final priceUzs = (record['price_uzs'] as num?)?.toDouble() ?? 0.0;
        final note = record['note'] as String?;
        final destination = record['destination'] as String?;
        final outboundReason = record['outbound_reason'] as String?;
        // ★ v6.6: 读取批次字段
        final supplier = record['supplier'] as String?;
        final batchNumber = record['batch_number'] as String?;
        final productionDateStr = record['production_date'] as String?;
        final expiryDateStr = record['expiry_date'] as String?;
        final createdAtStr = record['created_at'] as String?;  // ★ v6.11: 传原始创建时间

        // ★ 防御性去重检查
        final exists = await _defensiveDupCheck('stock_records_cloud', recordId);
        if (exists) {
          await _db.markRecordSynced(recordId);
          count++;
          continue;
        }

        bool success;
        if (type == 'inBound') {
          success = await syncStockIn(barcode, quantity,
              localRecordId: recordId,
              operatorName: opName,
              priceCny: priceCny,
              priceUzs: priceUzs,
              note: note,
              supplier: supplier,
              expiryDate: expiryDateStr,
              productionDate: productionDateStr,
              batchNumber: batchNumber,
              createdAt: createdAtStr);
        } else {
          success = await syncStockOut(barcode, quantity,
              localRecordId: recordId,
              operatorName: opName,
              priceCny: priceCny,
              priceUzs: priceUzs,
              note: note,
              destination: destination,
              outboundReason: outboundReason,
              expiryDate: expiryDateStr,
              productionDate: productionDateStr,
              batchNumber: batchNumber,
              supplier: supplier,
              createdAt: createdAtStr);
        }

        if (success) {
          count++;
        }
      } catch (e) {
        // 单条失败继续下一条
      }
    }

    return count;
  }

  // ==================== 出入库记录双向同步 ====================

  /// 从云端 stock_records_cloud 下载其他设备生成的出入库记录到本地
  ///
  /// ★ v6.31 核心逻辑：
  ///   - 本方法按 lastSyncTime 增量拉取，只处理安装/上次同步后产生的新流水。
  ///   - 全新设备首次同步时，由 downloadProducts() 用云端 products.stock 兜底初始化库存，
  ///     并设置 lastSyncTime，因此本方法不会重复应用历史流水，避免翻倍。
  ///   - 幂等查重：synced_cloud_records 按 cloud_id 去重 + 本地 barcode/type/quantity/operator 降级查重。
  Future<int> downloadStockRecords() async {
    try {
      final deviceId = await getDeviceId();
      final lastSyncTime = await _getLastStockSyncTime();
      final now = DateTime.now().toUtc();

      debugPrint('[Sync] downloadStockRecords: storeId=$_storeId, deviceId=$deviceId, lastSyncTime=$lastSyncTime');

      // 构建查询 URI，使用时间过滤（gt 严格大于）
      String timeFilter = '';
      if (lastSyncTime != null) {
        timeFilter = '&created_at=gt.${lastSyncTime.toUtc().toIso8601String()}';
      }

      // ★ v6.2 不指定 select：让 PostgREST 返回所有列，避免 select 里含 device_id/supplier
      // 等可能不存在的列导致 400 错误。代码用 as String? / as num? 容错处理缺失字段。
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stock_records_cloud'
        '?store_id=eq.$_storeId'
        '$timeFilter'
        '&order=created_at.asc'
        '&limit=500',
      );
      debugPrint('[Sync] downloadStockRecords: query=$uri');
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 20),
      );

      debugPrint('[Sync] downloadStockRecords: HTTP ${res.statusCode}, body length=${res.body.length}');

      if (res.statusCode != 200) return 0;

      final List<dynamic> cloudRecords = jsonDecode(res.body);
      debugPrint('[Sync] downloadStockRecords: fetched ${cloudRecords.length} records from cloud');
      int count = 0;
      int skippedOwn = 0;
      int skippedAlreadySynced = 0;
      int skippedDuplicate = 0;
      DateTime? latestProcessedTime;
      bool hasSkippedDueToMissingProduct = false;

      for (final cr in cloudRecords) {
        try {
          // ★ v6.4 修复根因②：cloud_id 统一用 String，兼容 UUID 和整数 ID
          final cloudId = cr['id']?.toString();
          final barcode = cr['barcode'] as String? ?? '';
          final type = cr['type'] as String? ?? '';
          final quantity = (cr['quantity'] as num?)?.toInt() ?? 0;
          final createdAtStr = cr['created_at'] as String? ?? '';
          final operatorName = cr['operator_name'] as String? ?? '云端同步';
          final cloudDeviceId = cr['device_id'] as String?;
          final cloudExpiryDate = cr['expiry_date'] as String?;

          debugPrint('[Sync] downloadStockRecords item: cloudId=$cloudId barcode=$barcode type=$type qty=$quantity expiryDate=$cloudExpiryDate');

          if (barcode.isEmpty || type.isEmpty || createdAtStr.isEmpty) continue;

          final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();  // ★ v6.11: 转本地时间
          if (createdAt == null) continue;

          // ★ v6.32: 跳过本机设备的记录（由 syncStockIn/syncStockOut 即时创建，已存在于本地）
          if (cloudDeviceId != null && cloudDeviceId == deviceId) {
            skippedOwn++;
            if (latestProcessedTime == null || createdAt.isAfter(latestProcessedTime)) {
              latestProcessedTime = createdAt;
            }
            continue;
          }

          // ★ v6.4 幂等查重 1：用 synced_cloud_records 表按云端 id 查重（cloud_id 为 String）
          if (cloudId != null && cloudId.isNotEmpty) {
            try {
              final alreadySynced =
                  await _db.isCloudRecordSynced(cloudId);
              if (alreadySynced) {
                // 已处理过，仅推进时间
                skippedAlreadySynced++;
                if (latestProcessedTime == null ||
                    createdAt.isAfter(latestProcessedTime)) {
                  latestProcessedTime = createdAt;
                }
                continue;
              }
            } catch (e) {
              debugPrint('[Sync] isCloudRecordSynced error: $e');
            }
          }

          // ★ v6.13 幂等查重 2（降级）：直接用 raw SQL 按 barcode+type+quantity+operator 查重
          // 不再依赖 created_at 字符串比较（UTC vs 本地时区格式不一致会导致比较失败）
          final db = await _db.database;
          final dupCheck = await db.rawQuery('''
            SELECT COUNT(*) as cnt FROM stock_records
            WHERE barcode = ? AND type = ? AND quantity = ? AND operator_name = ? AND is_batch_internal = 0
          ''', [barcode, type, quantity, operatorName]);
          final dupCount = (dupCheck.first['cnt'] as num?)?.toInt() ?? 0;
          final alreadyExists = dupCount > 0;

          if (alreadyExists) {
            // 标记为已处理，推进时间
            skippedDuplicate++;
            if (cloudId != null && cloudId.isNotEmpty) {
              try {
                await _db.markCloudRecordSynced(cloudId);
              } catch (e) {
                debugPrint('[Sync] markCloudRecordSynced error: $e');
              }
            }
            if (latestProcessedTime == null ||
                createdAt.isAfter(latestProcessedTime)) {
              latestProcessedTime = createdAt;
            }
            continue;
          }

          // ★ 找到本地商品ID，若本地无此商品先创建占位商品（治漏数据根因④）
          var localProduct = await _db.getProductByBarcode(barcode);
          if (localProduct == null) {
            // 本地无此商品 -> 尝试从云端 products 表获取真实名称
            String placeholderName = '未命名商品($barcode)';
            try {
              final nameLookupUri = Uri.parse(
                '${SupabaseConfig.restBaseUrl}/products?store_id=eq.$_storeId&barcode=eq.${Uri.encodeComponent(barcode)}&select=name&limit=1',
              );
              final nameLookupRes = await http.get(nameLookupUri, headers: _headers).timeout(const Duration(seconds: 5));
              if (nameLookupRes.statusCode == 200) {
                final List<dynamic> nameResult = jsonDecode(nameLookupRes.body);
                if (nameResult.isNotEmpty) {
                  final cloudProductName = nameResult.first['name'] as String?;
                  if (cloudProductName != null && cloudProductName.isNotEmpty) {
                    placeholderName = cloudProductName;
                    debugPrint('[Sync] downloadStockRecords: got real name from cloud for $barcode: "$placeholderName"');
                  }
                }
              }
            } catch (_) {}
            final placeholderId = await _db.insertProduct(Product(
              barcode: barcode,
              nameCn: placeholderName,
              category: '其他',
              priceCny: (cr['price_cny'] as num?)?.toDouble() ?? 0,
              priceUzs: (cr['price_uzs'] as num?)?.toDouble() ?? 0,
              unit: '个',
            ));
            localProduct = await _db.getProductById(placeholderId);
            if (localProduct == null) {
              // 创建失败，不推进时间，下次再试
              hasSkippedDueToMissingProduct = true;
              continue;
            }
          } else {
            // ★ v6.31 fix: 本地已有商品但价格为 0 时，从流水记录中补价格
            // 场景：A 手机入库设了价格但 cloud products 表暂未同步时，
            //        B 手机通过下载流水记录也能获得价格（双路径兜底）
            final recordPriceCny = (cr['price_cny'] as num?)?.toDouble() ?? 0;
            final recordPriceUzs = (cr['price_uzs'] as num?)?.toDouble() ?? 0;
            final needsPriceUpdate = (recordPriceCny > 0 && localProduct.priceCny == 0) ||
                (recordPriceUzs > 0 && localProduct.priceUzs == 0);
            if (needsPriceUpdate && localProduct.id != null) {
              await _db.updateProductPrices(
                localProduct.id!,
                recordPriceCny > 0 ? recordPriceCny : localProduct.priceCny,
                recordPriceUzs > 0 ? recordPriceUzs : localProduct.priceUzs,
              );
            }
          }

          // ★ 插入本地流水（显式 is_synced=1，治根因⑤）
          // ★ v6.6: 解析批次字段（expiry_date/production_date/batch_number/supplier）
          final record = StockRecord(
            productId: localProduct.id!,
            barcode: barcode,
            type: StockType.values.byName(type),
            quantity: quantity,
            priceCny: (cr['price_cny'] as num?)?.toDouble() ?? 0,
            priceUzs: (cr['price_uzs'] as num?)?.toDouble() ?? 0,
            costPriceCny: (cr['cost_price_cny'] as num?)?.toDouble() ?? 0,
            operatorName: operatorName,
            note: cr['note'] as String?,
            outboundReason: cr['outbound_reason'] != null
                ? OutboundReason.values.byName(cr['outbound_reason'] as String)
                : null,
            destination: cr['destination'] as String?,
            supplier: cr['supplier'] as String?,
            batchNumber: cr['batch_number'] as String?,
            productionDate: cr['production_date'] != null
                ? DateTime.tryParse(cr['production_date'] as String)
                : null,
            expiryDate: cr['expiry_date'] != null
                ? DateTime.tryParse(cr['expiry_date'] as String)
                : null,
            createdAt: createdAt,
            isSynced: true,
          );
          final localRecordId = await _db.insertStockRecordFromCloud(record);
          count++;

          // ★ 应用流水到本地库存
          if (type == 'inBound') {
            final localInv = await _db.getInventoryByProductId(localProduct.id!);
            if (localInv != null) {
              final newStock = localInv.currentQuantity + quantity;
              await _db.updateInventoryQuantity(localProduct.id!, newStock);
            } else {
              await _db.upsertInventory(Inventory(
                productId: localProduct.id!,
                barcode: barcode,
                currentQuantity: quantity,
              ));
            }
          } else {
            final localInv = await _db.getInventoryByProductId(localProduct.id!);
            if (localInv != null) {
              final newStock =
                  (localInv.currentQuantity - quantity).clamp(0, 999999);
              await _db.updateInventoryQuantity(localProduct.id!, newStock);
            }
            // ★ FIFO批次追踪，保证临期/过期跨设备同步
            final fifoAllocs = await _db.allocateOutboundByFIFO(localProduct.id!, quantity);
            for (final alloc in fifoAllocs) {
              final allocExpiry = alloc['expiry_date'] as String?;
              final allocQty = alloc['quantity'] as int;
              await _db.insertStockRecord(StockRecord(
                productId: localProduct.id!,
                barcode: barcode,
                type: StockType.outBound,
                quantity: allocQty,
                priceCny: record.priceCny,
                priceUzs: record.priceUzs,
                operatorName: operatorName,
                expiryDate: allocExpiry != null ? DateTime.tryParse(allocExpiry) : null,
                isBatchInternal: true,
                isSynced: true,
                createdAt: createdAt,
              ));
            }
          }

          // 标记云端记录为已处理（幂等，cloud_id 为 String）
          if (cloudId != null && cloudId.isNotEmpty) {
            try {
              await _db.markCloudRecordSynced(cloudId);
            } catch (e) {
              debugPrint('[Sync] markCloudRecordSynced error: $e');
            }
          }

          // 推进 latestProcessedTime
          if (latestProcessedTime == null ||
              createdAt.isAfter(latestProcessedTime)) {
            latestProcessedTime = createdAt;
          }
        } catch (e) {
          // 跳过解析失败的单条记录，但不推进时间
        }
      }

      debugPrint('[Sync] downloadStockRecords: DONE — downloaded=$count, skippedOwn=$skippedOwn, skippedAlreadySynced=$skippedAlreadySynced, skippedDuplicate=$skippedDuplicate, totalFetched=${cloudRecords.length}');

      // ★ 更新同步时间戳
      // v6.2 修复：若有因 localProduct==null 跳过的记录，不推进 lastSyncTime（下次再试）
      // 否则推进到最新处理时间 - 60秒安全裕量（容忍跨设备时钟偏差）
      if (!hasSkippedDueToMissingProduct && latestProcessedTime != null) {
        final safeTime = latestProcessedTime.subtract(const Duration(seconds: 60));
        await _setLastStockSyncTime(safeTime);
      } else if (cloudRecords.isEmpty && lastSyncTime == null) {
        // 首次同步且无记录时，记录当前时间避免下次重新全量拉取
        await _setLastStockSyncTime(now);
      }

      // ★ 处理完后，把本地库存回写云端（让云端 stock 反映最新状态）
      // 仅对本次下载涉及的条码回写，避免全量回写太慢
      // 此处简化：依赖 _syncLocalStockToCloud 在每条流水处理后已回写

      return count;
    } catch (e) {
      debugPrint('[Sync] downloadStockRecords error: $e');
      return 0;
    }
  }

  // ==================== 盘点任务双向同步 ====================

  /// 上传本地所有未同步的盘点任务到云端 check_tasks_cloud 表
  /// ★ v6.19: 上传已完成 + 已分配的待盘点任务
  /// - 已完成任务：以 completedAt 为同步锚点
  /// - 已分配任务（assignedTo!=null）：无论状态都上传，让被分配者能看到
  Future<int> uploadCheckTasks() async {
    try {
      // ★ v6.19: 已完成的任务
      final completedTasks = await _db.getCheckTasks(status: CheckTaskStatus.completed);
      // ★ v6.19: 已分配但未完成的任务（让员工手机能看到）
      final allTasks = await _db.getCheckTasks();
      final assignedPending = allTasks
          .where((t) => t.assignedTo != null && t.status != CheckTaskStatus.completed)
          .toList();

      // 合并去重（按 id）
      final seen = <int>{};
      final tasks = <CheckTask>[];
      for (final t in [...completedTasks, ...assignedPending]) {
        if (t.id != null && !seen.contains(t.id)) {
          seen.add(t.id!);
          tasks.add(t);
        }
      }

      int count = 0;

      for (final task in tasks) {
        try {
          final localTaskId = task.id!;
          final anchorTime = (task.completedAt ?? task.createdAt).toUtc().toIso8601String();
          final isCompleted = task.status == CheckTaskStatus.completed;

          // ★ v6.20: 先查找云端任务（本设备精确 + 跨设备 title+operator 兜底）
          String? cloudTaskId;
          String? cloudStatus;
          final cloudTask = await _lookupCloudTask(
            localTaskId,
            task.title,
            task.operatorName,
            status: isCompleted ? null : 'pending',
          );
          if (cloudTask != null) {
            cloudTaskId = cloudTask['id'];
            cloudStatus = cloudTask['status'];
          }

          if (cloudTaskId == null) {
            // ★ 云端不存在 → POST 新建
            // ★ v6.23: 将明细序列化为 JSON 嵌入 task 记录，一个 HTTP 请求解决上传问题
            final Map<String, dynamic> body = {
              'store_id': _storeId,
              'local_id': localTaskId,
              'title': task.title,
              'status': task.status.name,
              'operator_name': task.operatorName,
              'total_items': task.totalItems,
              'checked_items': task.checkedItems,
              'is_synced': 1,
              'created_at': anchorTime,
            };
            // ★ v6.25: 上传 assigned_to 字段，让被分配者能识别任务
            if (task.assignedTo != null && task.assignedTo!.isNotEmpty) {
              body['assigned_to'] = task.assignedTo;
            }
            if (isCompleted) {
              body['completed_at'] = task.completedAt?.toUtc().toIso8601String();
              // ★ v6.23: 关键修复 — 将明细数据嵌入 task 记录，不再依赖单独的 check_details_cloud 表
              final localDetails = await _db.getCheckDetailsByTaskId(localTaskId);
              if (localDetails.isNotEmpty) {
                body['details_json'] = jsonEncode(localDetails.map((d) => {
                  'barcode': d.barcode,
                  'product_id': d.productId,
                  'system_quantity': d.systemQuantity,
                  'actual_quantity': d.actualQuantity,
                  'difference': d.difference,
                  'note': d.note,
                  'shelf_location': d.shelfLocation,
                  'actual_expired_qty': d.actualExpiredQty,
                  'actual_near_expiry_qty': d.actualNearExpiryQty,
                }).toList());
                debugPrint('[Sync] uploadCheckTasks: embedding ${localDetails.length} details in task POST');
              }
            }

            final res = await _defensivePost(
              '/check_tasks_cloud',
              body,
              headers: _headersWithReturn,
            ).timeout(const Duration(seconds: 10));

            if (res.statusCode == 201 || res.statusCode == 200) {
              try {
                final List<dynamic> rows = jsonDecode(res.body);
                if (rows.isNotEmpty) cloudTaskId = rows.first['id']?.toString();
              } catch (_) {}
              count++;

              // cloudTaskId 提取失败时，回退查询云端获取
              if (cloudTaskId == null) {
                final fallback = await _lookupCloudTask(
                  localTaskId,
                  task.title,
                  task.operatorName,
                );
                if (fallback != null) {
                  cloudTaskId = fallback['id'];
                  cloudStatus = fallback['status'];
                }
              }
            }
          } else if (isCompleted && cloudStatus != 'completed') {
            // ★ 云端存在但状态还是 pending → PATCH 更新为 completed
            // ★ v6.23: 同时嵌入明细 JSON
            final Map<String, dynamic> patchBody = {
              'status': 'completed',
              'checked_items': task.checkedItems,
              'total_items': task.totalItems,
              'completed_at': task.completedAt?.toUtc().toIso8601String(),
            };
            final localDetails = await _db.getCheckDetailsByTaskId(localTaskId);
            if (localDetails.isNotEmpty) {
              patchBody['details_json'] = jsonEncode(localDetails.map((d) => {
                'barcode': d.barcode,
                'product_id': d.productId,
                'system_quantity': d.systemQuantity,
                'actual_quantity': d.actualQuantity,
                'difference': d.difference,
                'note': d.note,
                'shelf_location': d.shelfLocation,
                'actual_expired_qty': d.actualExpiredQty,
                'actual_near_expiry_qty': d.actualNearExpiryQty,
              }).toList());
              debugPrint('[Sync] uploadCheckTasks: embedding ${localDetails.length} details in task PATCH');
            }
            final patchUri = Uri.parse(
              '${SupabaseConfig.restBaseUrl}/check_tasks_cloud?id=eq.$cloudTaskId',
            );
            final patchRes = await http.patch(
              patchUri,
              headers: _headers,
              body: jsonEncode(patchBody),
            ).timeout(const Duration(seconds: 10));
            if (patchRes.statusCode == 200 || patchRes.statusCode == 204) {
              count++;
            }
          } else if (isCompleted && cloudStatus == 'completed') {
            // ★ v6.23: 云端已 completed 但可能没有 details_json → PATCH 补传明细
            final localDetails = await _db.getCheckDetailsByTaskId(localTaskId);
            if (localDetails.isNotEmpty) {
              final Map<String, dynamic> patchBody = {
                'details_json': jsonEncode(localDetails.map((d) => {
                  'barcode': d.barcode,
                  'product_id': d.productId,
                  'system_quantity': d.systemQuantity,
                  'actual_quantity': d.actualQuantity,
                  'difference': d.difference,
                  'note': d.note,
                  'shelf_location': d.shelfLocation,
                  'actual_expired_qty': d.actualExpiredQty,
                  'actual_near_expiry_qty': d.actualNearExpiryQty,
                }).toList()),
              };
              final patchUri = Uri.parse(
                '${SupabaseConfig.restBaseUrl}/check_tasks_cloud?id=eq.$cloudTaskId',
              );
              final patchRes = await http.patch(
                patchUri,
                headers: _headers,
                body: jsonEncode(patchBody),
              ).timeout(const Duration(seconds: 10));
              if (patchRes.statusCode == 200 || patchRes.statusCode == 204) {
                debugPrint('[Sync] uploadCheckTasks: patched details_json for existing task $cloudTaskId');
              }
            }
          }

          // ★ v6.23: 明细已嵌入 task 记录，不再需要单独调用 uploadCheckDetails
          // check_details_cloud 表仅作为本地备份，跨设备同步走 details_json 字段
        } catch (e) {
          debugPrint('[Sync] uploadCheckTasks item error: $e');
        }
      }
      return count;
    } catch (e) {
      debugPrint('[Sync] uploadCheckTasks error: $e');
      return 0;
    }
  }

  /// 上传指定盘点任务的所有明细到云端 check_details_cloud 表
  /// ★ v6.4: cloudTaskId 改为 String，兼容 UUID
  /// ★ v6.21: 增加 force 参数，支持强制覆盖
  /// ★ v6.22: 改为批量上传（一次 HTTP POST 写入全部明细），大幅降低逐条上传的网络失败概率
  Future<int> uploadCheckDetails(int localTaskId, String cloudTaskId, {bool force = false}) async {
    try {
      final details = await _db.getCheckDetailsByTaskId(localTaskId);
      if (details.isEmpty) {
        debugPrint('[Sync] uploadCheckDetails: no local details for task $cloudTaskId');
        return 0;
      }

      // ★ v6.22: 先删除云端该任务已有的明细（以本地为权威）
      try {
        final deleteUri = Uri.parse(
          '${SupabaseConfig.restBaseUrl}/check_details_cloud'
          '?store_id=eq.$_storeId'
          '&task_id=eq.$cloudTaskId',
        );
        final deleteRes = await http.delete(deleteUri, headers: _headers).timeout(
          const Duration(seconds: 10),
        );
        debugPrint('[Sync] uploadCheckDetails: cleared existing, HTTP ${deleteRes.statusCode}');
      } catch (e) {
        debugPrint('[Sync] uploadCheckDetails: clear error: $e');
      }

      // ★ v6.22: 批量上传 — 一次 POST 写入全部明细，避免逐条 HTTP 往返导致部分失败
      final int taskIdNumeric = int.tryParse(cloudTaskId) ?? 0;
      final List<Map<String, dynamic>> batch = [];
      for (final d in details) {
        final Map<String, dynamic> body = {
          'store_id': _storeId,
          'task_id': taskIdNumeric > 0 ? taskIdNumeric : cloudTaskId,
          'product_id': d.productId > 0 ? d.productId : 0,
          'barcode': d.barcode,
          'system_quantity': d.systemQuantity,
          'actual_quantity': d.actualQuantity,
          'difference': d.difference,
          'is_synced': 1,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        final note = d.note;
        if (note != null && note.isNotEmpty) body['note'] = note;
        final shelfLocation = d.shelfLocation;
        if (shelfLocation != null && shelfLocation.isNotEmpty) body['shelf_location'] = shelfLocation;
        batch.add(body);
      }

      final uri = Uri.parse('${SupabaseConfig.restBaseUrl}/check_details_cloud');
      final batchBody = jsonEncode(batch);
      debugPrint('[Sync] uploadCheckDetails: batch POST ${batch.length} details, body size=${batchBody.length} bytes');

      try {
        final res = await http.post(
          uri,
          headers: _headers,
          body: batchBody,
        ).timeout(const Duration(seconds: 30));

        if (res.statusCode == 201 || res.statusCode == 200 || res.statusCode == 204) {
          debugPrint('[Sync] uploadCheckDetails: batch POST OK, HTTP ${res.statusCode}, uploaded ${details.length} details for task $cloudTaskId');
          return details.length;
        } else {
          debugPrint('[Sync] uploadCheckDetails: batch POST FAILED, HTTP ${res.statusCode} body=${res.body}');
          // ★ 批量失败回退：逐条重试
          int count = 0;
          for (final body in batch) {
            try {
              final r = await http.post(uri, headers: _headers, body: jsonEncode(body))
                  .timeout(const Duration(seconds: 10));
              if (r.statusCode == 201 || r.statusCode == 200 || r.statusCode == 204) count++;
            } catch (_) {}
          }
          debugPrint('[Sync] uploadCheckDetails: fallback one-by-one uploaded $count/${details.length}');
          return count;
        }
      } catch (e) {
        debugPrint('[Sync] uploadCheckDetails: batch POST exception: $e');
        // 批量失败回退逐条
        int count = 0;
        for (final body in batch) {
          try {
            final r = await http.post(uri, headers: _headers, body: jsonEncode(body))
                .timeout(const Duration(seconds: 10));
            if (r.statusCode == 201 || r.statusCode == 200 || r.statusCode == 204) count++;
          } catch (_) {}
        }
        debugPrint('[Sync] uploadCheckDetails: fallback one-by-one uploaded $count/${details.length}');
        return count;
      }
    } catch (e) {
      debugPrint('[Sync] uploadCheckDetails error: $e');
      return 0;
    }
  }

  /// 从云端 check_tasks_cloud 下载其他设备的盘点任务到本地
  /// ★ v6.25: 移除 created_at 时间过滤——改为下载全部未过滤任务，由本地 title+operator 去重
  /// 修复：A 创建任务后 B 在任务上传前同步过一次，导致后续 B 的 lastSyncTime > 任务 created_at，
  /// 任务被时间过滤永远遗漏
  Future<int> downloadCheckTasks() async {
    try {
      final deviceId = await getDeviceId();

      // ★ v6.25: 不按时间过滤，下载全部盘点任务。本地有去重逻辑（title+operator），不担心重复。
      // 盘点任务最多几十条，全量下载没有性能问题。
      final taskUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/check_tasks_cloud'
        '?store_id=eq.$_storeId'
        '&order=created_at.desc'
        '&limit=100',
      );
      final taskRes = await http.get(taskUri, headers: _headers).timeout(
        const Duration(seconds: 15),
      );

      if (taskRes.statusCode != 200) return 0;

      final List<dynamic> cloudTasks = jsonDecode(taskRes.body);
      int count = 0;
      DateTime? latestTaskTime;

      for (final ct in cloudTasks) {
        try {
          final cloudDeviceId = ct['device_id'] as String?;
          final taskTitle = ct['title'] as String? ?? '';
          final createdAtStr = ct['created_at'] as String? ?? '';
          if (taskTitle.isEmpty || createdAtStr.isEmpty) continue;
          final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
          if (createdAt == null) continue;

          // ★ v6.24: 本设备的任务不直接跳过——如果云端状态被其他设备更新了
          // （如店长分配任务给员工，员工完成后更新了云端状态），需要同步到本地
          final isOwnDevice = cloudDeviceId != null && cloudDeviceId == deviceId;
          if (isOwnDevice) {
            // 更新 latestTaskTime
            if (latestTaskTime == null || createdAt.isAfter(latestTaskTime)) {
              latestTaskTime = createdAt;
            }
            // ★ v6.24: 检查本地任务状态是否需要从云端同步更新
            final cloudStatusStr = ct['status'] as String? ?? 'pending';
            final existingTasks = await _db.getCheckTasks(status: null);
            final existingMatch = existingTasks.where((t) =>
                t.title == taskTitle &&
                t.operatorName == (ct['operator_name'] as String? ?? ''));
            bool needsSync = false;
            for (final existing in existingMatch) {
              if (cloudStatusStr == 'completed' && existing.status.name != 'completed') {
                needsSync = true;
                break;
              }
            }
            if (!needsSync) continue;
            // 需要同步 → 不跳过，继续走下面的匹配/更新逻辑
          }

          // ★ v6.29: 检查用户是否已删除此任务（本地删除后防止云端重新下载）
          final cloudOperatorName = ct['operator_name'] as String? ?? '';
          final isDeleted = await _db.isCheckTaskDeleted(taskTitle, cloudOperatorName);
          if (isDeleted) {
            debugPrint('[Sync] downloadCheckTasks: skipping deleted task "$taskTitle" by $cloudOperatorName');
            if (latestTaskTime == null || createdAt.isAfter(latestTaskTime)) {
              latestTaskTime = createdAt;
            }
            continue;
          }

          // ★ v6.16: 用 title+operatorName 去重（cloud created_at 改用 completedAt，时间不匹配）
          final existingTasks = await _db.getCheckTasks(status: null);
          final existingMatch = existingTasks.where((t) =>
              t.title == taskTitle &&
              t.operatorName == cloudOperatorName);
          var matched = false;
          int? matchedLocalId;
          for (final existing in existingMatch) {
            matched = true;
            matchedLocalId = existing.id;
            // ★ v6.17: 仅当云端=completed且本地≠completed时更新（不降级）
            final cloudStatusStr = ct['status'] as String? ?? 'pending';
            if (cloudStatusStr == 'completed' && existing.status.name != 'completed' && existing.id != null) {
              final updatedTask = existing.copyWith(
                status: CheckTaskStatus.completed,
                checkedItems: (ct['checked_items'] as num?)?.toInt() ?? existing.checkedItems,
                totalItems: (ct['total_items'] as num?)?.toInt() ?? existing.totalItems,
                completedAt: ct['completed_at'] != null
                    ? DateTime.tryParse(ct['completed_at'] as String)
                    : existing.completedAt,
              );
              await _db.updateCheckTask(updatedTask);
              count++;
            }
            break;
          }

          if (matched) {
            // ★ v6.23: 匹配到本地任务时，尝试从 details_json 下载明细
            final detailsJson = ct['details_json'];
            if (detailsJson != null && matchedLocalId != null) {
              await _insertDetailsFromJson(matchedLocalId, detailsJson);
            } else {
              // ★ 兜底：如果 details_json 为空，尝试从 check_details_cloud 拉取明细
              final cloudTaskId = ct['id']?.toString();
              if (cloudTaskId != null && cloudTaskId.isNotEmpty && matchedLocalId != null) {
                await downloadCheckDetails(cloudTaskId: cloudTaskId, insertedLocalTaskId: matchedLocalId);
              }
            }
            if (latestTaskTime == null ||
                createdAt.isAfter(latestTaskTime)) {
              latestTaskTime = createdAt;
            }
            continue;
          }

          final task = CheckTask(
            title: taskTitle,
            status: CheckTaskStatus.values.byName(
              ct['status'] as String? ?? 'pending',
            ),
            operatorName: ct['operator_name'] as String? ?? '云端同步',
            assignedTo: ct['assigned_to'] as String?,
            categoryFilter: ct['category_filter'] as String?,
            shelfFilter: ct['shelf_filter'] as String?,
            startedAt: ct['started_at'] != null
                ? DateTime.tryParse(ct['started_at'] as String)
                : null,
            totalItems: (ct['total_items'] as num?)?.toInt() ?? 0,
            checkedItems: (ct['checked_items'] as num?)?.toInt() ?? 0,
            createdAt: createdAt,
            completedAt: ct['completed_at'] != null
                ? DateTime.tryParse(ct['completed_at'] as String)
                : null,
          );

          final localTaskId = await _db.insertCheckTask(task);
          count++;

          // ★ v6.23: 优先从 details_json 下载明细（与任务一起上传，必定存在）
          final detailsJson = ct['details_json'];
          if (detailsJson != null) {
            await _insertDetailsFromJson(localTaskId, detailsJson);
          } else {
            // 兜底：尝试从 check_details_cloud 拉取明细
            final cloudTaskId = ct['id']?.toString();
            if (cloudTaskId != null && cloudTaskId.isNotEmpty) {
              await downloadCheckDetails(cloudTaskId: cloudTaskId, insertedLocalTaskId: localTaskId);
            }
          }

          if (latestTaskTime == null || createdAt.isAfter(latestTaskTime)) {
            latestTaskTime = createdAt;
          }
        } catch (e) {
          // 跳过解析失败的单条
        }
      }

      // ★ v6.25: 不再需要时间过滤。始终下载全部盘点任务，_fullSync 首轮也会重置时间戳。
      // 保留 _setLastCheckSyncTime 调用以确保 _checkVersionAndForceResync 逻辑正常工作
      await _setLastCheckSyncTime(latestTaskTime ?? DateTime.now().toUtc());

      return count;
    } catch (e) {
      debugPrint('[Sync] downloadCheckTasks error: $e');
      return 0;
    }
  }

  /// ★ v6.23: 从 JSON 字符串解析盘点明细并插入本地数据库
  /// detailsJson 可以是 String 或 List<dynamic>（PostgREST 解析后）
  Future<int> _insertDetailsFromJson(int localTaskId, dynamic detailsJson) async {
    try {
      List<dynamic> list;
      if (detailsJson is String) {
        list = jsonDecode(detailsJson) as List<dynamic>;
      } else if (detailsJson is List) {
        list = detailsJson;
      } else {
        return 0;
      }
      if (list.isEmpty) return 0;

      // 先删除该任务的旧明细，再写入新明细
      await _db.deleteCheckDetailsByTaskId(localTaskId);
      int count = 0;
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final barcode = item['barcode'] as String? ?? '';
        if (barcode.isEmpty) continue;
        final localProduct = await _db.getProductByBarcode(barcode);
        await _db.insertCheckDetail(CheckDetail(
          taskId: localTaskId,
          productId: localProduct?.id ?? (item['product_id'] as num?)?.toInt() ?? 0,
          barcode: barcode,
          systemQuantity: (item['system_quantity'] as num?)?.toInt() ?? 0,
          actualQuantity: (item['actual_quantity'] as num?)?.toInt() ?? 0,
          difference: (item['difference'] as num?)?.toInt() ?? 0,
          note: item['note'] as String?,
          shelfLocation: item['shelf_location'] as String?,
          actualExpiredQty: (item['actual_expired_qty'] as num?)?.toInt(),
          actualNearExpiryQty: (item['actual_near_expiry_qty'] as num?)?.toInt(),
        ));
        count++;
      }
      debugPrint('[Sync] _insertDetailsFromJson: inserted $count details for localTaskId=$localTaskId');
      return count;
    } catch (e) {
      debugPrint('[Sync] _insertDetailsFromJson error: $e');
      return 0;
    }
  }

  /// 从云端 check_details_cloud 下载指定任务的盘点明细
  /// ★ v6.4: cloudTaskId 改为 String，兼容 UUID
  Future<int> downloadCheckDetails({
    required String cloudTaskId,
    required int insertedLocalTaskId,
  }) async {
    try {
      final detailUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/check_details_cloud'
        '?store_id=eq.$_storeId'
        '&task_id=eq.$cloudTaskId'
        '&order=created_at.asc'
        '&limit=500',
      );
      final detailRes = await http.get(detailUri, headers: _headers).timeout(
        const Duration(seconds: 15),
      );

      if (detailRes.statusCode != 200) return 0;

      final List<dynamic> cloudDetails = jsonDecode(detailRes.body);
      int count = 0;

      // ★ v6.21: 无条件清空本地该任务的旧明细，再以云端为权威写入
      // 这样即使云端明细为空，也会把本地残留脏数据清空，避免"已删除的明细还在"
      try {
        await _db.deleteCheckDetailsByTaskId(insertedLocalTaskId);
        debugPrint('[Sync] downloadCheckDetails: cleared local details for localTaskId=$insertedLocalTaskId');
      } catch (e) {
        debugPrint('[Sync] downloadCheckDetails clear local error: $e');
      }

      for (final cd in cloudDetails) {
        try {
          final detailBarcode = cd['barcode'] as String? ?? '';
          if (detailBarcode.isEmpty) continue;

          final localProduct = await _db.getProductByBarcode(detailBarcode);
          final localProductId =
              localProduct?.id ?? (cd['product_id'] as num?)?.toInt() ?? 0;

          await _db.insertCheckDetail(CheckDetail(
            taskId: insertedLocalTaskId,
            productId: localProductId,
            barcode: detailBarcode,
            systemQuantity: (cd['system_quantity'] as num?)?.toInt() ?? 0,
            actualQuantity: (cd['actual_quantity'] as num?)?.toInt() ?? 0,
            difference: (cd['difference'] as num?)?.toInt() ?? 0,
            note: cd['note'] as String?,
            shelfLocation: cd['shelf_location'] as String?,
            actualExpiredQty: (cd['actual_expired_qty'] as num?)?.toInt(),
            actualNearExpiryQty: (cd['actual_near_expiry_qty'] as num?)?.toInt(),
          ));
          count++;
        } catch (e) {
          // 单条失败继续
        }
      }
      debugPrint('[Sync] downloadCheckDetails: cloudTaskId=$cloudTaskId localTaskId=$insertedLocalTaskId downloaded=$count');
      return count;
    } catch (e) {
      debugPrint('[Sync] downloadCheckDetails error: $e');
      return 0;
    }
  }

  // ==================== 盘点差异上传（遗留兼容） ====================

  Future<bool> uploadDifferenceReport({
    required String? productId,
    required int systemStock,
    required int actualStock,
  }) async {
    try {
      final difference = actualStock - systemStock;
      if (difference == 0) return true;

      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/difference_reports',
      );
      final body = jsonEncode({
        'store_id': _storeId,
        'product_id': null,
        'system_stock': systemStock,
        'actual_stock': actualStock,
        'difference': difference,
      });
      final res = await http.post(uri, headers: _headers, body: body).timeout(
        const Duration(seconds: 10),
      );
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('[Sync] uploadDifferenceReport error: $e');
      return false;
    }
  }

  // ==================== 全量同步 ====================

  /// 执行完整的同步流程（轮询时调用）：
  /// ★ v6.2 流程调整：先下载商品、再下载流水（确保 localProduct 存在再应用流水）
  ///
  /// 1. 上传本地未同步的出入库记录
  /// 2. 上传盘点任务
  /// 3. 从云端下载商品基础信息（不初始化本地库存，库存由流水驱动）
  /// 4. 从云端下载其他设备的出入库记录（幂等查重 + 应用本地库存 + 回写云端）
  /// 5. 从云端下载其他设备的盘点任务
  /// 6. 同步云端用户到本地
  Future<SupabaseSyncResult> fullSync() async {
    try {
      await _ensureStoreId();  // ★ v6.31 fix
      debugPrint('[Sync] ========== fullSync START ==========');
      final parts = <String>[];

      // 第一步：上传本地未同步的出入库记录
      final uploadedRecords = await uploadPendingStockRecords();
      debugPrint('[Sync] fullSync: uploadedRecords=$uploadedRecords');
      if (uploadedRecords > 0) {
        parts.add('上传 $uploadedRecords 条出入库记录');
      }

      // 第二步：上传盘点任务
      final uploadedChecks = await uploadCheckTasks();
      debugPrint('[Sync] fullSync: uploadedChecks=$uploadedChecks');
      if (uploadedChecks > 0) {
        parts.add('上传 $uploadedChecks 个盘点任务');
      }

      // ★ 第三步：先下载商品（确保 localProduct 存在，避免流水被跳过）
      final downloadedProducts = await downloadProducts();
      debugPrint('[Sync] fullSync: downloadedProducts=$downloadedProducts');
      if (downloadedProducts > 0) {
        parts.add('下载 $downloadedProducts 个商品');
      }

      // ★ v6.31 新增：从云端下载当前门店信息（名称等），写入 SharedPreferences
      await _downloadStoreInfo();

      // ★ 第四步：下载其他设备的出入库记录（应用本地库存）
      final downloadedRecords = await downloadStockRecords();
      debugPrint('[Sync] fullSync: downloadedRecords=$downloadedRecords');
      if (downloadedRecords > 0) {
        parts.add('同步 $downloadedRecords 条出入库记录');
      }

      // 第五步：下载其他设备的盘点任务
      final downloadedChecks = await downloadCheckTasks();
      debugPrint('[Sync] fullSync: downloadedChecks=$downloadedChecks');
      if (downloadedChecks > 0) {
        parts.add('同步 $downloadedChecks 个盘点任务');
      }

      // 第六步：同步云端用户到本地
      final downloadedUsers = await downloadUsers();
      debugPrint('[Sync] fullSync: downloadedUsers=$downloadedUsers');
      if (downloadedUsers > 0) {
        parts.add('同步 $downloadedUsers 个用户');
      }

      debugPrint('[Sync] ========== fullSync DONE: ${parts.join(', ')} ==========');

      return SupabaseSyncResult(
        success: true,
        uploadedStockRecords: uploadedRecords,
        uploadedCheckTasks: uploadedChecks,
        downloadedProducts: downloadedProducts,
        syncedStockCount: downloadedProducts,
        downloadedStockRecords: downloadedRecords,
        downloadedChecks: downloadedChecks,
        message: parts.isNotEmpty
            ? '同步完成: ${parts.join('，')}'
            : '同步完成，无新数据',
      );
    } catch (e) {
      return SupabaseSyncResult(
        success: false,
        message: '同步失败: $e',
      );
    }
  }

  // ==================== 用户同步 ====================

  Future<bool> uploadUser(local_user.User user) async {
    try {
      final userBarcode = '__user:${user.username}__';
      // ★ v6.31: 上传密码哈希值，不再上传明文
      final userData = jsonEncode({
        'displayName': user.displayName,
        'passwordHash': user.passwordHash,
        'passwordSalt': user.passwordSalt,
        'phone': user.phone,
        'role': user.role.name,
        'isActive': user.isActive,
      });

      final lookupUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/products?store_id=eq.$_storeId&barcode=eq.${Uri.encodeComponent(userBarcode)}&select=id',
      );
      final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
        const Duration(seconds: 10),
      );

      if (lookupRes.statusCode == 200) {
        final List<dynamic> existing = jsonDecode(lookupRes.body);
        if (existing.isNotEmpty) {
          final cloudId = existing.first['id'] as String;
          final updateRes = await http.patch(
            Uri.parse('${SupabaseConfig.restBaseUrl}/products?id=eq.$cloudId'),
            headers: _headers,
            body: jsonEncode({
              'name': userData,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }),
          ).timeout(const Duration(seconds: 10));
          return updateRes.statusCode == 200 || updateRes.statusCode == 204;
        }
      }

      final createRes = await http.post(
        Uri.parse('${SupabaseConfig.restBaseUrl}/products'),
        headers: _headers,
        body: jsonEncode({
          'store_id': _storeId,
          'barcode': userBarcode,
          'name': userData,
          'price': 0,
          'unit': 'user',
          'stock': 1,
          'is_active': true,
        }),
      ).timeout(const Duration(seconds: 10));
      return createRes.statusCode == 201;
    } catch (e) {
      debugPrint('[Sync] uploadDifferenceReport error: $e');
      return false;
    }
  }

  Future<int> downloadUsers() async {
    try {
      final uri = Uri.parse(SupabaseConfig.restBaseUrl).replace(
        path: '/rest/v1/products',
        queryParameters: {
          'store_id': 'eq.$_storeId',
          'barcode': 'like.__user:%',
          'select': 'id,barcode,name',
        },
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 15),
      );

      if (res.statusCode != 200) return 0;

      final List<dynamic> cloudUsers = jsonDecode(res.body);
      int count = 0;

      for (final cu in cloudUsers) {
        final barcode = cu['barcode'] as String? ?? '';
        final nameJson = cu['name'] as String?;
        if (barcode.isEmpty || nameJson == null) continue;

        final username = barcode.replaceAll('__user:', '').replaceAll('__', '');
        if (username.isEmpty) continue;

        try {
          final data = jsonDecode(nameJson) as Map<String, dynamic>;
          final existing = await _db.getUserByUsername(username);
          if (existing == null) {
            await _db.insertUser(local_user.User(
              username: username,
              displayName: data['displayName'] as String? ?? username,
              passwordHash: data['passwordHash'] as String?,
              passwordSalt: data['passwordSalt'] as String?,
              role: local_user.UserRole.values.byName(
                data['role'] as String? ?? 'stockKeeper',
              ),
              phone: data['phone'] as String?,
              isActive: data['isActive'] as bool? ?? true,
            ));
            count++;
          } else if (existing.passwordHash == null && data['passwordHash'] != null) {
            await _db.updateUserPassword(
              existing.id!,
              data['passwordHash'] as String,
              data['passwordSalt'] as String? ?? '',
            );
            count++;
          }
        } catch (e) {
          // 跳过解析失败的单条记录
        }
      }

      return count;
    } catch (e) {
      debugPrint('[Sync] downloadUsers error: $e');
      return 0;
    }
  }

  /// ★ v6.31 fix: 在所有门店中按手机号查找员工（新手机不用先选超市）
  /// 返回 {user, store_id}，找不到返回 null
  Future<Map<String, dynamic>?> findUserByPhoneOnCloudAnyStore(String phone) async {
    try {
      // 不指定 store_id，依赖 RLS 的 anon 策略允许读取所有 __user:% 记录
      final uri = Uri.parse(SupabaseConfig.restBaseUrl).replace(
        path: '/rest/v1/products',
        queryParameters: {
          'barcode': 'like.__user:%',
          'select': 'barcode,name,store_id',
        },
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 15),
      );

      if (res.statusCode != 200) {
        debugPrint('[Sync] findUserByPhoneOnCloudAnyStore HTTP ${res.statusCode}: ${res.body}');
        return null;
      }

      final List<dynamic> cloudUsers = jsonDecode(res.body);
      for (final cu in cloudUsers) {
        final nameJson = cu['name'] as String?;
        if (nameJson == null) continue;

        try {
          final data = jsonDecode(nameJson) as Map<String, dynamic>;
          if (data['phone'] == phone) {
            final username = (cu['barcode'] as String)
                .replaceAll('__user:', '')
                .replaceAll('__', '');
            final foundUser = local_user.User(
              username: username,
              displayName: data['displayName'] as String? ?? username,
              passwordHash: data['passwordHash'] as String?,
              passwordSalt: data['passwordSalt'] as String?,
              role: local_user.UserRole.values.byName(
                data['role'] as String? ?? 'stockKeeper',
              ),
              phone: data['phone'] as String?,
              isActive: data['isActive'] as bool? ?? true,
            );
            return {
              'user': foundUser,
              'store_id': cu['store_id'] as String? ?? 'main',
            };
          }
        } catch (e) {
          continue;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Sync] findUserByPhoneOnCloudAnyStore error: $e');
      return null;
    }
  }

  Future<local_user.User?> findUserByPhoneOnCloud(String phone) async {
    final result = await findUserByPhoneOnCloudAnyStore(phone);
    return result?['user'] as local_user.User?;
  }

  // ==================== 预置商品上传 ====================

  Future<int> uploadPresetProducts() async {
    try {
      final localProducts = await _db.getAllProducts();
      int count = 0;

      for (final p in localProducts) {
        if (p.barcode.startsWith('__')) continue;

        final lookupUri = Uri.parse(
          '${SupabaseConfig.restBaseUrl}/products?store_id=eq.$_storeId&barcode=eq.${p.barcode}&select=id',
        );
        final lookupRes = await http.get(lookupUri, headers: _headers).timeout(
          const Duration(seconds: 10),
        );

        if (lookupRes.statusCode == 200) {
          final List<dynamic> existing = jsonDecode(lookupRes.body);
          if (existing.isNotEmpty) continue;
        }

        final body = jsonEncode({
          'store_id': _storeId,
          'barcode': p.barcode,
          'name': p.nameCn,
          'category_name': p.category.isNotEmpty ? p.category : '其他',
          'price': p.priceUzs,
          'cost_price': p.costPriceCny,
          'unit': p.unit ?? '个',
          'stock': 0,
          'min_stock': 10,
          'is_active': true,
        });
        final createRes = await http.post(
          Uri.parse('${SupabaseConfig.restBaseUrl}/products'),
          headers: _headers,
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (createRes.statusCode == 201) count++;
      }

      return count;
    } catch (e) {
      debugPrint('[Sync] uploadPresetProducts error: $e');
      return 0;
    }
  }

  // ==================== ★ v6.3: 多店管理 ====================

  /// 上传当前超市信息到云端 stores 表（幂等）
  ///
  /// 在 InitWizard 注册新超市时调用。
  /// stores 表结构见 supabase_complete_upgrade.sql Part 3。
  Future<bool> uploadStoreInfo({
    required String storeId,
    required String name,
    String? address,
    String? phone,
    String? managerName,
    String countryCode = 'CN',
  }) async {
    try {
      // 先查是否已存在
      final checkUri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId&select=store_id&limit=1',
      );
      final checkRes = await http.get(checkUri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (checkRes.statusCode == 200) {
        final List existing = jsonDecode(checkRes.body);
        if (existing.isNotEmpty) {
          // 已存在，upsert 更新名称等字段
          final patchRes = await http.patch(
            Uri.parse('${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'address': address,
              'phone': phone,
              'manager_name': managerName,
              'country_code': countryCode,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }),
          ).timeout(const Duration(seconds: 8));
          return patchRes.statusCode == 200;
        }
      }

      // 不存在，插入新记录
      final res = await http.post(
        Uri.parse('${SupabaseConfig.restBaseUrl}/stores'),
        headers: _headers,
        body: jsonEncode({
          'store_id': storeId,
          'name': name,
          'address': address,
          'phone': phone,
          'manager_name': managerName,
          'country_code': countryCode,
          'is_active': true,
        }),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('[Sync] uploadDifferenceReport error: $e');
      return false;
    }
  }

  /// ★ v6.31: 检查手机号是否已被其他超市注册（注册前校验）
  /// 返回已使用的 store_id，如果未使用则返回 null
  Future<String?> checkPhoneInCloudStores(String phone) async {
    if (phone.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?phone=eq.${Uri.encodeComponent(phone)}&select=store_id,name&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          return data.first['store_id'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Sync] checkPhoneInCloudStores error: $e');
      return null; // 网络异常不阻止注册
    }
  }

  /// 从云端拉取所有超市列表（员工手机加入超市时用）
  Future<List<Map<String, dynamic>>> downloadStoreList() async {
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?is_active=eq.true&select=store_id,name,address,manager_name,phone&order=name.asc',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 10),
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// ★ v6.31: 从云端下载当前门店的名称等基本信息，写入 SharedPreferences
  /// 解决 B 手机登录后看板显示默认名称的问题
  /// ★ v6.32 (方案C): 同时下载 country_code，使国家配置跨设备同步
  Future<void> _downloadStoreInfo() async {
    try {
      final storeId = _storeId;
      if (storeId.isEmpty || storeId == 'main') return;

      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId&select=name,country_code&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode != 200) return;

      final List data = jsonDecode(res.body);
      if (data.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();

      // 同步门店名称
      final storeName = data[0]['name'] as String?;
      if (storeName != null && storeName.isNotEmpty) {
        await prefs.setString('store_name', storeName);
        debugPrint('[Sync] _downloadStoreInfo: store_name=$storeName saved to prefs');
      }

      // ★ v6.32 (方案C): 同步国家配置
      final cloudCountryCode = data[0]['country_code'] as String?;
      if (cloudCountryCode != null && cloudCountryCode.isNotEmpty) {
        final currentCode = prefs.getString('country_code') ?? 'CN';
        if (currentCode != cloudCountryCode) {
          await prefs.setString('country_code', cloudCountryCode);
          debugPrint('[Sync] _downloadStoreInfo: country_code updated $currentCode → $cloudCountryCode');
        }
      }
    } catch (e) {
      debugPrint('[Sync] _downloadStoreInfo error: $e');
    }
  }

  /// ★ v6.31: 根据 store_id 查云端门店名称（用于登录时同步）
  Future<String?> getStoreNameById(String storeId) async {
    try {
      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId&select=name&limit=1',
      );
      final res = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (res.statusCode != 200) return null;
      final List data = jsonDecode(res.body);
      if (data.isEmpty) return null;
      return data[0]['name'] as String?;
    } catch (e) {
      debugPrint('[Sync] getStoreNameById error: $e');
      return null;
    }
  }

  /// ★ v6.32 (方案C): 将当前国家配置上传到云端 stores 表
  /// 使得同一超市的其他手机能同步到正确的国家/货币配置
  Future<bool> uploadCountryCode(String countryCode) async {
    try {
      await _ensureStoreId();
      final storeId = _storeId;
      if (storeId.isEmpty || storeId == 'main') return false;

      final uri = Uri.parse(
        '${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId&select=store_id&limit=1',
      );
      final checkRes = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (checkRes.statusCode != 200) return false;
      final List existing = jsonDecode(checkRes.body);
      if (existing.isEmpty) return false;

      final patchRes = await http.patch(
        Uri.parse('${SupabaseConfig.restBaseUrl}/stores?store_id=eq.$storeId'),
        headers: _headers,
        body: jsonEncode({
          'country_code': countryCode,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 8));
      debugPrint('[Sync] uploadCountryCode: store_id=$storeId country_code=$countryCode status=${patchRes.statusCode}');
      return patchRes.statusCode == 200 || patchRes.statusCode == 204;
    } catch (e) {
      debugPrint('[Sync] uploadCountryCode error: $e');
      return false;
    }
  }
}
