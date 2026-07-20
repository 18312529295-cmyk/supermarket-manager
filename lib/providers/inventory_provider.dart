import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/inventory.dart';
import '../models/stock_record.dart';
import '../models/order.dart';
import '../models/check_task.dart';
import '../models/shelf.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../providers/app_provider.dart';

class InventoryProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final SyncService _sync = SyncService();

  AppProvider? _appProvider;

  /// ★ v6.32: 设置 AppProvider 引用，用于同步后刷新国家配置等
  void setAppProvider(AppProvider appProvider) {
    _appProvider = appProvider;
  }

  List<Map<String, dynamic>> _inventoryList = [];
  List<Map<String, dynamic>> get inventoryList => _inventoryList;

  Map<String, dynamic> _dashboardStats = {};
  Map<String, dynamic> get dashboardStats => _dashboardStats;

  List<Product> _products = [];
  List<Product> get products => _products;

  List<CheckTask> _checkTasks = [];
  List<CheckTask> get checkTasks => _checkTasks;

  List<Shelf> _shelves = [];
  List<Shelf> get shelves => _shelves;

  List<StockRecord> _stockRecords = [];
  List<StockRecord> get stockRecords => _stockRecords;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  /// ★ v6.31: 库存不足警告（出库时库存不够，UI可监听此字段弹提示）
  String? _stockShortageWarning;
  String? get stockShortageWarning => _stockShortageWarning;

  /// ★ 消费警告后清除
  void clearWarning() {
    _stockShortageWarning = null;
    notifyListeners();
  }

  // ==================== DASHBOARD ====================

  Future<void> loadDashboardStats() async {
    _isLoading = true;
    notifyListeners();
    try {
      _dashboardStats = await _db.getDashboardStats();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  // ==================== PRODUCTS ====================

  Future<void> loadProducts({String? category, String? search}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _products = await _db.getAllProducts(category: category, search: search);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Product?> findProductByBarcode(String barcode) async {
    return await _db.getProductByBarcode(barcode);
  }

  Future<int> addProduct(Product product) async {
    final id = await _db.insertProduct(product);
    await loadProducts();
    return id;
  }

  Future<int> updateProduct(Product product) async {
    final result = await _db.updateProduct(product);
    await loadProducts();
    return result;
  }

  // ==================== INVENTORY ====================

  Future<void> loadInventory({String? category, String? shelfLocation, bool lowStockOnly = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _inventoryList = await _db.getInventoryWithProduct(
        category: category,
        shelfLocation: shelfLocation,
        lowStockOnly: lowStockOnly,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateStockQuantity(int productId, int newQuantity) async {
    await _db.updateInventoryQuantity(productId, newQuantity);
    await loadInventory();
  }

  // ==================== STOCK IN/OUT ====================

  Future<void> recordStockIn(StockRecord record) async {
    final recordId = await _db.insertStockRecord(record);

    // Update inventory
    final inv = await _db.getInventoryByProductId(record.productId);
    if (inv != null) {
      await _db.updateInventoryQuantity(
        record.productId,
        inv.currentQuantity + record.quantity,
      );
    } else {
      await _db.upsertInventory(Inventory(
        productId: record.productId,
        barcode: record.barcode,
        currentQuantity: record.quantity,
      ));
    }

    // 同步保质期到商品表（临期预警依赖此字段）
    if (record.expiryDate != null) {
      final product = await _db.getProductById(record.productId);
      if (product != null && product.expiryDate == null) {
        await _db.updateProduct(product.copyWith(
          expiryDate: record.expiryDate,
          updatedAt: DateTime.now(),
        ));
      }
    }

    await loadInventory();
    await loadDashboardStats();

    // ★ 即时同步到云（syncStockIn 已自带幂等检查 + 自动标记已同步）
    _sync.syncStockIn(record.barcode, record.quantity,
        localRecordId: recordId,
        operatorName: record.operatorName,
        priceCny: record.priceCny,
        priceUzs: record.priceUzs,
        note: record.note,
        supplier: record.supplier,
        expiryDate: record.expiryDate?.toIso8601String(),
        productionDate: record.productionDate?.toIso8601String(),
        batchNumber: record.batchNumber);
  }

  Future<void> recordStockOut(StockRecord record) async {
    // ★ v6.32: 出库时后台记录当前进价（用于盈利计算，员工不可见）
    final currentCost = await _db.getProductCostPrice(record.productId);
    final recordWithCost = currentCost != null && currentCost > 0
        ? record.copyWith(costPriceCny: currentCost)
        : record;

    // ★ v6.7 修复：单条主记录显示 + FIFO批次追踪记录（仅用于临期扣减）
    // 1) 插入1条主记录（isBatchInternal=false）用于显示+同步
    // 2) 获取FIFO分配，插入批次追踪记录（isBatchInternal=true, 仅用于getBatchNearExpiry/getBatchExpired扣减）
    final recordId = await _db.insertStockRecord(recordWithCost);

    // ★ FIFO批次追踪：插入内部追踪记录（不显示在UI，不参与同步，仅用于临期扣减计算）
    final allocations = await _db.allocateOutboundByFIFO(record.productId, record.quantity);
    for (final alloc in allocations) {
      final expiryStr = alloc['expiry_date'] as String?;
      final qty = alloc['quantity'] as int;
      await _db.insertStockRecord(record.copyWith(
        quantity: qty,
        expiryDate: expiryStr != null ? DateTime.tryParse(expiryStr) : null,
        isBatchInternal: true,
        isSynced: true, // 标记为已同步，不被上传
      ));
    }

    // Update inventory — ★ v6.29 直接扣减逻辑（已验证同步正常）
    final inv = await _db.getInventoryByProductId(record.productId);
    if (inv != null) {
      final newQty = inv.currentQuantity - record.quantity;
      await _db.updateInventoryQuantity(
        record.productId,
        newQty >= 0 ? newQty : 0,
      );
    }

    await loadInventory();
    await loadDashboardStats();

    // ★ 即时同步到云（只同步主记录）
    _sync.syncStockOut(record.barcode, record.quantity,
        localRecordId: recordId,
        operatorName: record.operatorName,
        priceCny: record.priceCny,
        priceUzs: record.priceUzs,
        costPriceCny: recordWithCost.costPriceCny,
        note: record.note,
        destination: record.destination,
        outboundReason: record.outboundReason?.name,
        expiryDate: record.expiryDate?.toIso8601String(),
        productionDate: record.productionDate?.toIso8601String(),
        batchNumber: record.batchNumber,
        supplier: record.supplier).then((ok) {
    });
  }

  Future<void> loadStockRecords({StockType? type}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _stockRecords = await _db.getStockRecords(type: type);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  // ==================== ORDERS (v6.33) ====================

  List<Order> _orders = [];
  List<Order> get orders => _orders;

  List<Map<String, dynamic>> _ordersWithItems = [];
  List<Map<String, dynamic>> get ordersWithItems => _ordersWithItems;

  /// 创建新订单并返回订单ID
  Future<int> createOrder(String customerName, String operatorName) async {
    final order = Order(
      customerName: customerName,
      operatorName: operatorName,
    );
    final orderId = await _db.insertOrder(order);
    await loadOrdersWithItems();
    return orderId;
  }

  /// 向订单添加商品
  Future<void> addItemToOrder(StockRecord record, int orderId) async {
    final recordWithOrderId = record.copyWith(orderId: orderId);
    await recordStockOut(recordWithOrderId);
    await _db.updateOrderTotals(orderId);
    await loadOrdersWithItems();
  }

  /// 加载所有订单及明细
  Future<void> loadOrdersWithItems() async {
    _ordersWithItems = await _db.getOrdersWithItems(limit: 100);
    notifyListeners();
  }

  /// 获取指定订单的明细
  Future<List<StockRecord>> getOrderItems(int orderId) async {
    return await _db.getStockRecordsByOrderId(orderId);
  }

  // ==================== CHECK TASKS ====================

  Future<void> loadCheckTasks({CheckTaskStatus? status}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _checkTasks = await _db.getCheckTasks(status: status);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<int> createCheckTask(CheckTask task) async {
    final id = await _db.insertCheckTask(task);
    await loadCheckTasks();
    return id;
  }

  Future<void> updateCheckTask(CheckTask task) async {
    await _db.updateCheckTask(task);
    await loadCheckTasks();
  }

  /// ★ v6.17: 删除盘点任务
  Future<void> deleteCheckTask(int taskId) async {
    // ★ v6.29: 删除前记录任务信息，防止云端同步重新下载
    final task = await _db.getCheckTaskById(taskId);
    if (task != null) {
      await _db.markCheckTaskDeleted(task.title, task.operatorName);
    }
    await _db.deleteCheckTask(taskId);
    await loadCheckTasks();
  }

  Future<void> submitCheckResult(int taskId, List<CheckDetail> details) async {
    for (final detail in details) {
      await _db.insertCheckDetail(detail);
    }

    final task = await _db.getCheckTaskById(taskId);
    if (task != null) {
      await _db.updateCheckTask(task.copyWith(
        status: CheckTaskStatus.completed,
        completedAt: DateTime.now(),
        checkedItems: details.length,
      ));
    }

    await loadCheckTasks();

    // ★ v6.24: 同步改为 fire-and-forget，不阻塞提交成功的 UI 反馈
    // 30 秒轮询的 fullSync 也会覆盖上传，这里只做尽早同步
    _sync.syncCheckTasks().catchError((e) {
      debugPrint('[Provider] submitCheckResult syncCheckTasks error: $e');
    });
  }

  Future<Map<String, dynamic>> getCheckSummary(int taskId) async {
    return await _db.getCheckSummary(taskId);
  }

  Future<List<CheckDetail>> getCheckDetails(int taskId) async {
    return await _db.getCheckDetailsByTaskId(taskId);
  }

  // ==================== SHELVES ====================

  Future<void> loadShelves() async {
    _isLoading = true;
    notifyListeners();
    try {
      _shelves = await _db.getAllShelves();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<int> addShelf(Shelf shelf) async {
    final id = await _db.insertShelf(shelf);
    await loadShelves();
    return id;
  }

  /// ★ v6.27: 更新/删除货架
  Future<void> updateShelf(Shelf shelf) async {
    await _db.updateShelf(shelf);
    await loadShelves();
  }

  Future<void> deleteShelf(int shelfId) async {
    await _db.deleteShelf(shelfId);
    await loadShelves();
  }

  /// ★ v6.27: 获取库存>0商品的货架列表
  Future<List<String>> getActiveShelfCodes() => _db.getActiveShelfCodes();

  /// ★ v6.27: 获取未盘点的商品
  Future<List<Map<String, dynamic>>> getUncheckedProducts(List<String> barcodes) =>
      _db.getUncheckedProducts(barcodes);

  Future<void> bindProductToShelf(ShelfBinding binding) async {
    await _db.insertShelfBinding(binding);
  }

  Future<void> deleteShelfBinding(int bindingId) async {
    final db = await _db.database;
    await db.delete('shelf_bindings', where: 'id = ?', whereArgs: [bindingId]);
  }

  Future<List<Map<String, dynamic>>> getShelfWithProducts() async {
    return await _db.getShelfWithProducts();
  }

  Future<List<Product>> getUnpricedProducts() => _db.getUnpricedProducts();

  Future<void> updateProductPrices(int productId, double priceCny, double priceUzs, {double costPriceCny = 0}) async {
    await _db.updateProductPrices(productId, priceCny, priceUzs, costPriceCny: costPriceCny);
  }

  Future<void> batchRenameZone(String oldZone, String newZone) async {
    await _db.batchRenameZone(oldZone, newZone);
    await loadShelves();
  }

  Future<void> deleteZone(String zone) async {
    await _db.deleteShelvesByZone(zone);
    await loadShelves();
  }

  // ==================== SYNC ====================

  /// ★ v6.10: 同步版本号，每次成功同步后+1
  /// 历史页面（入库/出库/盘点）监听此值变化来刷新列表
  int _syncVersion = 0;
  int get syncVersion => _syncVersion;

  Future<SyncResult> syncPendingData() async {
    final result = await _sync.syncPendingRecords();
    // ★ 同步完成后自动刷新看板统计数据和历史列表
    if (result.success) {
      _syncVersion++;
      await loadDashboardStats();
      await loadCheckTasks();

      // ★ v6.32 (方案C): 同步后检查国家配置，强制重算价格
      try {
        if (_appProvider != null) {
          final prefs = await SharedPreferences.getInstance();
          final syncedCountry = prefs.getString('country_code') ?? 'CN';
          if (_appProvider!.countryCode != syncedCountry) {
            await _appProvider!.setCountry(syncedCountry);
            debugPrint('[InventoryProvider] country_code synced: $syncedCountry');
          }
          // 不管 country 有没有变，强制重算一遍价格（保证一致性）
          await _appProvider!.forceRecalcPrices();
        }
      } catch (_) {}

      notifyListeners();
    }
    return result;
  }

  Future<int> getPendingSyncCount() async {
    return await _sync.getPendingSyncCount();
  }

  // ==================== 详情查询 ====================

  /// 获取单条出入库记录详情（含商品名称）
  Future<Map<String, dynamic>?> getStockRecordDetail(int id) async {
    return await _db.getStockRecordById(id);
  }

  /// 获取盘点任务详情
  Future<Map<String, dynamic>?> getCheckTaskDetail(int id) async {
    return await _db.getCheckTaskDetailById(id);
  }

  /// 获取盘点明细详情
  Future<Map<String, dynamic>?> getCheckDetailById(int id) async {
    return await _db.getCheckDetailById(id);
  }
}
