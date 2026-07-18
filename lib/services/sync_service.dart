import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import 'supabase_sync_service.dart';

class SyncService {
  final DatabaseService _db = DatabaseService.instance;
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();
  final Connectivity _connectivity = Connectivity();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// FIX: connectivity_plus v6+ returns List<ConnectivityResult> instead of
  /// a single ConnectivityResult. This helper handles both cases at runtime.
  bool _evaluateConnectivity(dynamic result) {
    if (result is List<ConnectivityResult>) {
      // v6+: result is a list; offline when it contains ConnectivityResult.none
      return !result.contains(ConnectivityResult.none);
    }
    // Fallback for older versions returning a single ConnectivityResult
    return result != ConnectivityResult.none;
  }

  Stream<bool> get connectivityStream async* {
    await for (final result in _connectivity.onConnectivityChanged) {
      // connectivity_plus v6+ emits List<ConnectivityResult>
      _isOnline = _evaluateConnectivity(result);
      yield _isOnline;
    }
  }

  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    // connectivity_plus v6+ returns List<ConnectivityResult>
    _isOnline = _evaluateConnectivity(result);
    return _isOnline;
  }

  // ==================== 即时同步（入库/出库后立即调用） ====================

  /// ★ 入库后即时同步云端库存（异步，传递完整参数）
  /// ★ v6.11: 新增 createdAt 参数，传递记录原始创建时间（修复跨设备时差）
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
    // ★ v6.31: 移除 connectivity 检查，直接尝试上传
    // checkConnectivity 在部分设备上可能误判，Supabase HTTP 自带超时
    return await _supabaseSync.syncStockIn(
      barcode,
      quantity,
      localRecordId: localRecordId,
      operatorName: operatorName,
      priceCny: priceCny,
      priceUzs: priceUzs,
      note: note,
      supplier: supplier,
      expiryDate: expiryDate,
      productionDate: productionDate,
      batchNumber: batchNumber,
      createdAt: createdAt,
    );
  }

  /// ★ 出库后即时同步云端库存（异步，传递完整参数）
  /// ★ v6.11: 新增 createdAt 参数
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
    // ★ v6.31: 移除 connectivity 检查，直接尝试上传
    return await _supabaseSync.syncStockOut(
      barcode,
      quantity,
      localRecordId: localRecordId,
      operatorName: operatorName,
      priceCny: priceCny,
      priceUzs: priceUzs,
      costPriceCny: costPriceCny,
      note: note,
      destination: destination,
      outboundReason: outboundReason,
      expiryDate: expiryDate,
      productionDate: productionDate,
      batchNumber: batchNumber,
      supplier: supplier,
      createdAt: createdAt,
    );
  }

  // ==================== 批量同步（手动触发） ====================

  /// 从云端下载最新数据（轮询调用，只下载不上传）
  Future<SyncResult> syncPendingRecords() async {
    try {
      final result = await _supabaseSync.fullSync();
      return SyncResult(
        success: result.success,
        syncedCount: result.downloadedProducts,
        message: result.message,
      );
    } catch (e) {
      return SyncResult(success: false, message: '同步失败: $e');
    }
  }

  Future<SyncResult> fullSync() async {
    try {
      final result = await _supabaseSync.fullSync();
      return SyncResult(
        success: result.success,
        syncedCount: result.downloadedProducts,
        message: result.message,
      );
    } catch (e) {
      return SyncResult(success: false, message: '完整同步失败: $e');
    }
  }

  /// 仅下载云端商品库（含库存覆盖）
  Future<SyncResult> downloadProducts() async {
    try {
      final count = await _supabaseSync.downloadProducts();
      return SyncResult(
        success: true,
        syncedCount: count,
        message: count > 0 ? '已同步 $count 个商品' : '无新商品',
      );
    } catch (e) {
      return SyncResult(success: false, message: '下载失败: $e');
    }
  }

  /// ★ 同步盘点任务：上传本地盘点任务到云端，同时下载其他设备的盘点任务
  Future<SyncResult> syncCheckTasks() async {
    try {
      final uploadCount = await _supabaseSync.uploadCheckTasks();
      final downloadCount = await _supabaseSync.downloadCheckTasks();
      final totalCount = uploadCount + downloadCount;
      return SyncResult(
        success: true,
        syncedCount: totalCount,
        message: '盘点任务同步完成: 上传 $uploadCount, 下载 $downloadCount',
      );
    } catch (e) {
      return SyncResult(success: false, message: '盘点任务同步失败: $e');
    }
  }

  /// ★ 下载其他设备的出入库记录
  Future<SyncResult> downloadStockRecords() async {
    try {
      final count = await _supabaseSync.downloadStockRecords();
      return SyncResult(
        success: true,
        syncedCount: count,
        message: count > 0 ? '已下载 $count 条出入库记录' : '无新记录',
      );
    } catch (e) {
      return SyncResult(success: false, message: '下载出入库记录失败: $e');
    }
  }

  Future<int> getPendingSyncCount() async {
    final records = await _db.getUnsyncedRecords();
    return records.length;
  }

  /// 上传盘点差异
  Future<bool> uploadDifference({
    required String? productId,
    required int systemStock,
    required int actualStock,
  }) async {
    return await _supabaseSync.uploadDifferenceReport(
      productId: productId,
      systemStock: systemStock,
      actualStock: actualStock,
    );
  }
}

class SyncResult {
  final bool success;
  final int syncedCount;
  final String message;

  SyncResult({
    required this.success,
    this.syncedCount = 0,
    required this.message,
  });
}
