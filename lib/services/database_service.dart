import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../models/inventory.dart';
import '../models/shelf.dart';
import '../models/stock_record.dart';
import '../models/order.dart';
import '../models/check_task.dart';
import '../models/user.dart';
import '../utils/password_util.dart';

class DatabaseService {
  static Database? _db;
  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'supermarket.db');

    return await openDatabase(
      path,
      version: 17,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        name_cn TEXT NOT NULL,
        name_ru TEXT,
        name_uz TEXT,
        foreign_name TEXT,
        category TEXT NOT NULL,
        shelf_location TEXT,
        price_cny REAL NOT NULL DEFAULT 0,
        price_uzs REAL NOT NULL DEFAULT 0,
        cost_price_cny REAL NOT NULL DEFAULT 0,
        unit TEXT,
        supplier TEXT,
        production_date TEXT,
        expiry_date TEXT,
        shelf_life_days INTEGER DEFAULT 0,
        unit_big TEXT,
        unit_small TEXT,
        unit_ratio INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Inventory table
    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        current_quantity INTEGER NOT NULL DEFAULT 0,
        min_stock_level INTEGER DEFAULT 10,
        shelf_location TEXT,
        last_updated TEXT NOT NULL,
        last_checked_at TEXT,
        checked_quantity INTEGER,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    // Shelves table
    await db.execute('''
      CREATE TABLE shelves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        zone TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Shelf bindings table
    await db.execute('''
      CREATE TABLE shelf_bindings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        shelf_code TEXT NOT NULL,
        row INTEGER,
        column INTEGER,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    // Stock records table
    await db.execute('''
      CREATE TABLE stock_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price_cny REAL NOT NULL DEFAULT 0,
        price_uzs REAL NOT NULL DEFAULT 0,
        cost_price_cny REAL DEFAULT 0,
        outbound_reason TEXT,
        destination TEXT,
        supplier TEXT,
        batch_number TEXT,
        production_date TEXT,
        expiry_date TEXT,
        operator_name TEXT NOT NULL,
        note TEXT,
        order_id INTEGER,         -- ★ v6.33: 所属订单ID
        is_synced INTEGER DEFAULT 0,
        is_batch_internal INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    
    // ★ v6.33: Orders table (订单头)
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        total_amount_cny REAL NOT NULL DEFAULT 0,
        total_amount_uzs REAL NOT NULL DEFAULT 0,
        operator_name TEXT NOT NULL,
        note TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Check tasks table
    await db.execute('''
      CREATE TABLE check_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        category_filter TEXT,
        shelf_filter TEXT,
        operator_name TEXT NOT NULL,
        total_items INTEGER DEFAULT 0,
        checked_items INTEGER DEFAULT 0,
        started_at TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL,
        assigned_to TEXT
      )
    ''');

    // Check details table
    await db.execute('''
      CREATE TABLE check_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        system_quantity INTEGER NOT NULL,
        actual_quantity INTEGER NOT NULL,
        difference INTEGER NOT NULL,
        note TEXT,
        actual_expired_qty INTEGER,
        actual_near_expiry_qty INTEGER,
        shelf_location TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES check_tasks(id) ON DELETE CASCADE
      )
    ''');

    // Users table
    // ★ v6.31: password → password_hash + password_salt（SHA-256 哈希存储，不再存明文）
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        password_hash TEXT,
        password_salt TEXT,
        role TEXT NOT NULL,
        phone TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_login_at TEXT
      )
    ''');

    // Operation logs table
    await db.execute('''
      CREATE TABLE operation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        username TEXT NOT NULL,
        action TEXT NOT NULL,
        detail TEXT,
        barcode TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ★ v6.2 新增：synced_cloud_records 表，记录已处理的云端流水 id，用于幂等去重
    // 避免跨设备同步时重复应用同一条云端流水导致翻倍
    await db.execute('''
      CREATE TABLE IF NOT EXISTS synced_cloud_records (
        cloud_id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL DEFAULT 'stock_records_cloud',
        local_record_id INTEGER,
        synced_at TEXT NOT NULL
      )
    ''');

    // ★ v6.29: deleted_check_tasks 表，记住用户删除的盘点任务
    // 防止本地删除后，云端同步重新下载回来
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_check_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        operator_name TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');

    // Insert default admin user（密码哈希存储）
    const _defaultAdminPassword = 'admin123';
    final _adminSalt = PasswordUtil.generateSalt();
    final _adminHash = PasswordUtil.hashPassword(_defaultAdminPassword, _adminSalt);
    await db.insert('users', {
      'username': 'admin',
      'display_name': '系统管理员',
      'password_hash': _adminHash,
      'password_salt': _adminSalt,
      'role': 'admin',
      'phone': '',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Insert sample categories and shelves for demo
    await _insertSampleData(db);

    // Import preset products from bundled JSON
    await _importPresetProducts(db);
  }

  /// 从 assets/preset_products.json 导入预置商品数据
  Future<void> _importPresetProducts(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/preset_products.json');
      final List<dynamic> items = jsonDecode(jsonString);
      final now = DateTime.now().toIso8601String();

      for (final item in items) {
        final barcode = item['barcode']?.toString() ?? '';
        final name = item['name_cn']?.toString() ?? '';
        if (barcode.isEmpty || name.isEmpty) continue;

        try {
          await db.insert('products', {
            'barcode': barcode,
            'name_cn': name,
            'name_ru': item['name_ru'],
            'name_uz': item['name_uz'],
            'category': item['category']?.toString() ?? '其他',
            'shelf_location': null,
            'price_cny': 0.0,
            'price_uzs': 0.0,
            'unit': item['unit']?.toString() ?? '瓶/包',
            'supplier': item['brand']?.toString(),
            'production_date': null,
            'expiry_date': null,
            'shelf_life_days': 0,
            'created_at': now,
            'updated_at': now,
          });
        } catch (e) {
          // 忽略重复条码
        }
      }
    } catch (e) {
      // 如果assets文件不存在则静默跳过
    }
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 -> v2: 导入预置商品数据
      await _importPresetProducts(db);
    }
    if (oldVersion < 3) {
      // v2 -> v3: users表增加password字段，并给admin设置默认密码
      // ★ v6.31: 旧迁移保留兼容（用于从极旧版本升级的场景），但不再操作
      try {
        await db.execute('ALTER TABLE users ADD COLUMN password TEXT');
        await db.update(
          'users',
          {'password': 'admin123'},
          where: 'username = ?',
          whereArgs: ['admin'],
        );
      } catch (e) {
        // 列已存在则忽略
      }
    }
    if (oldVersion < 4) {
      // v3 -> v4: users表增加phone字段（手机号登录用）
      try {
        await db.execute('ALTER TABLE users ADD COLUMN phone TEXT');
      } catch (e) {}
    }
    if (oldVersion < 5) {
      // v4 -> v5: products表增加复合单位字段
      try {
        await db.execute('ALTER TABLE products ADD COLUMN unit_big TEXT');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE products ADD COLUMN unit_small TEXT');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE products ADD COLUMN unit_ratio INTEGER');
      } catch (e) {}
    }
    if (oldVersion < 6) {
      // v5 -> v6: check_details表增加额外字段（实际过期/临期数量、货架位置）
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN actual_expired_qty INTEGER');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN actual_near_expiry_qty INTEGER');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN shelf_location TEXT');
      } catch (e) {}
    }
    if (oldVersion < 7) {
      // v6 -> v7: 再次确保check_details字段存在（兼容某些设备migration未成功的情况）
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN actual_expired_qty INTEGER');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN actual_near_expiry_qty INTEGER');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE check_details ADD COLUMN shelf_location TEXT');
      } catch (e) {}
    }
    if (oldVersion < 8) {
      // ★ v7 -> v8: 新增 synced_cloud_records 表，用于跨设备同步幂等去重
      // 解决"同一个超市不同手机之间数据同步"问题：按云端记录 id 去重，
      // 避免重复应用流水导致翻倍，也避免业务字段+时间窗口去重误杀跨设备流水
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS synced_cloud_records (
            cloud_id TEXT PRIMARY KEY,
            table_name TEXT NOT NULL DEFAULT 'stock_records_cloud',
            local_record_id INTEGER,
            synced_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
    }
    if (oldVersion < 9) {
      // ★ v8 -> v9: synced_cloud_records 表 cloud_id 改为 TEXT（兼容 UUID）
      // SQLite 不支持 ALTER COLUMN，需要重建表
      try {
        await db.execute('ALTER TABLE synced_cloud_records RENAME TO synced_cloud_records_old');
        await db.execute('''
          CREATE TABLE synced_cloud_records (
            cloud_id TEXT PRIMARY KEY,
            table_name TEXT NOT NULL DEFAULT 'stock_records_cloud',
            local_record_id INTEGER,
            synced_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          INSERT OR IGNORE INTO synced_cloud_records (cloud_id, table_name, local_record_id, synced_at)
          SELECT CAST(cloud_id AS TEXT), table_name, local_record_id, synced_at
          FROM synced_cloud_records_old
        ''');
        await db.execute('DROP TABLE synced_cloud_records_old');
      } catch (e) {
        // 如果迁移失败（表不存在等），直接创建新表
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS synced_cloud_records (
              cloud_id TEXT PRIMARY KEY,
              table_name TEXT NOT NULL DEFAULT 'stock_records_cloud',
              local_record_id INTEGER,
              synced_at TEXT NOT NULL
            )
          ''');
        } catch (e2) {}
      }
    }
    if (oldVersion < 10) {
      // ★ v9 -> v10: stock_records 新增 is_batch_internal 列（批次追踪标记）
      try {
        await db.execute(
          'ALTER TABLE stock_records ADD COLUMN is_batch_internal INTEGER DEFAULT 0',
        );
      } catch (e) {}
    }
    if (oldVersion < 11) {
      // ★ v10 -> v11: check_tasks 新增 assigned_to 列（店长分配盘点任务给员工）
      try {
        await db.execute(
          'ALTER TABLE check_tasks ADD COLUMN assigned_to TEXT',
        );
      } catch (e) {}
    }
    if (oldVersion < 12) {
      // ★ v11 -> v12: deleted_check_tasks 表，记住用户删除的盘点任务
      // 防止本地删除后，云端同步重新下载回来
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS deleted_check_tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            operator_name TEXT NOT NULL,
            deleted_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN foreign_name TEXT');
      } catch (e) {}
      try {
        await db.execute(
          "UPDATE products SET foreign_name = COALESCE(NULLIF(name_ru,''), name_uz) WHERE foreign_name IS NULL"
        );
      } catch (e) {}
    }
    if (oldVersion < 14) {
      // ★ v6.31: v13 → v14 — 密码安全升级：从明文改为 SHA-256 + salt 哈希存储
      try {
        await db.execute('ALTER TABLE users ADD COLUMN password_hash TEXT');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN password_salt TEXT');
      } catch (e) {}
      // 迁移已有明文密码 → hash+salt（仅当 password_hash 为空且 password 不为空时）
      final usersWithPassword = await db.rawQuery(
        "SELECT id, password FROM users WHERE password IS NOT NULL AND password != '' AND (password_hash IS NULL OR password_hash = '')"
      );
      for (final u in usersWithPassword) {
        final plainPassword = u['password'] as String;
        final salt = PasswordUtil.generateSalt();
        final hash = PasswordUtil.hashPassword(plainPassword, salt);
        await db.update('users', {
          'password_hash': hash,
          'password_salt': salt,
        }, where: 'id = ?', whereArgs: [u['id']]);
      }
    }
    if (oldVersion < 15) {
      // ★ v6.31: v14 → v15 — 商品进价字段
      try {
        await db.execute('ALTER TABLE products ADD COLUMN cost_price_cny REAL NOT NULL DEFAULT 0');
      } catch (e) {}
    }
    if (oldVersion < 16) {
      // ★ v6.32: v15 → v16 — 出库记录进价字段（盈利计算用）
      try {
        await db.execute('ALTER TABLE stock_records ADD COLUMN cost_price_cny REAL DEFAULT 0');
      } catch (e) {}
    }
    if (oldVersion < 17) {
      // ★ v6.33: v16 → v17 — Orders表 + order_id字段
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_name TEXT NOT NULL,
            total_amount_cny REAL NOT NULL DEFAULT 0,
            total_amount_uzs REAL NOT NULL DEFAULT 0,
            operator_name TEXT NOT NULL,
            note TEXT,
            is_synced INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('ALTER TABLE stock_records ADD COLUMN order_id INTEGER');
      } catch (e) {}
    }
  }

  Future<void> _insertSampleData(Database db) async {
    final categories = ['饮料', '零食', '调味品', '日用品', '冷冻食品', '粮油'];
    final zones = ['A区-主货架', 'B区-冷藏柜', 'C区-干货区', 'D区-收银台附近'];

    for (int i = 0; i < zones.length; i++) {
      await db.insert('shelves', {
        'code': 'S${(i + 1).toString().padLeft(2, '0')}',
        'name': zones[i].split('-').last,
        'zone': zones[i].split('-').first,
        'description': '',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // ==================== PRODUCTS ====================

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.insert('products', product.toMap());
  }

  /// ★ v6.32: 获取商品当前进价（用于出库时记录成本）
  Future<double?> getProductCostPrice(int productId) async {
    final db = await database;
    final result = await db.query(
      'products',
      columns: ['cost_price_cny'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return (result.first['cost_price_cny'] as num?)?.toDouble();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Product.fromMap(maps.first);
  }

  Future<List<Product>> getAllProducts({String? category, String? search}) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;

    if (category != null && search != null && search.isNotEmpty) {
      where = 'category = ? AND (name_cn LIKE ? OR barcode LIKE ? OR name_ru LIKE ? OR name_uz LIKE ?)';
      whereArgs = [category, '%$search%', '%$search%', '%$search%', '%$search%'];
    } else if (category != null) {
      where = 'category = ?';
      whereArgs = [category];
    } else if (search != null && search.isNotEmpty) {
      where = 'name_cn LIKE ? OR barcode LIKE ? OR name_ru LIKE ? OR name_uz LIKE ?';
      whereArgs = ['%$search%', '%$search%', '%$search%', '%$search%'];
    }

    final maps = await db.query('products', where: where, whereArgs: whereArgs);
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.update(
      'products',
      product.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  /// ★ v6.31: 清除复合单位（copyWith 无法用 null 清除??语义字段）
  Future<void> clearProductCompositeUnit(int productId) async {
    final db = await database;
    await db.update(
      'products',
      {'unit_big': null, 'unit_small': null, 'unit_ratio': null},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT category FROM products ORDER BY category',
    );
    return result.map((r) => r['category'] as String).toList();
  }

  // ==================== INVENTORY ====================

  Future<int> upsertInventory(Inventory inventory) async {
    final db = await database;
    final existing = await db.query(
      'inventory',
      where: 'product_id = ?',
      whereArgs: [inventory.productId],
    );
    if (existing.isEmpty) {
      return await db.insert('inventory', inventory.toMap());
    } else {
      return await db.update(
        'inventory',
        inventory.toMap(),
        where: 'product_id = ?',
        whereArgs: [inventory.productId],
      );
    }
  }

  Future<Inventory?> getInventoryByProductId(int productId) async {
    final db = await database;
    final maps = await db.query(
      'inventory',
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Inventory.fromMap(maps.first);
  }

  /// ★ v6.9 精确计算某条 record 操作前的库存
  /// 用 stock_records 中该 record 之前所有主记录（is_batch_internal=0）的净变化量
  /// ★ v6.12: 重写 — 直接用 id < recordId 排除当前记录，无需子查询
  /// 逻辑：SUM(所有该商品、is_batch_internal=0、id < 本记录) = 操作前库存
  Future<int> getStockBeforeRecord(int productId, int recordId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type='inBound' THEN quantity ELSE -quantity END), 0)
      FROM stock_records
      WHERE product_id = ? AND is_batch_internal = 0 AND id < ?
    ''', [productId, recordId]);
    return (result.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> getInventoryWithProduct({String? category, String? shelfLocation, bool lowStockOnly = false, String? search}) async {
    final db = await database;
    String where = '1=1';
    List<Object?> args = [];

    if (category != null) {
      where += ' AND p.category = ?';
      args.add(category);
    }
    if (shelfLocation != null) {
      where += ' AND i.shelf_location = ?';
      args.add(shelfLocation);
    }
    if (lowStockOnly) {
      where += ' AND i.current_quantity <= COALESCE(i.min_stock_level, 10)';
    }
    /// ★ v6.31: 搜索支持 — 按商品名称或条码模糊匹配
    if (search != null && search.isNotEmpty) {
      where += ' AND (p.name_cn LIKE ? OR p.barcode LIKE ?)';
      final likeStr = '%$search%';
      args.add(likeStr);
      args.add(likeStr);
    }

    return await db.rawQuery('''
      SELECT i.*, p.name_cn, p.name_ru, p.name_uz, p.category, p.price_cny, p.price_uzs, p.expiry_date,
        p.unit_big, p.unit_small, p.unit_ratio, p.cost_price_cny
      FROM inventory i
      INNER JOIN products p ON i.product_id = p.id
      WHERE $where
      ORDER BY p.category, p.name_cn
    ''', args);
  }

  Future<int> updateInventoryQuantity(int productId, int newQuantity) async {
    final db = await database;
    return await db.update(
      'inventory',
      {
        'current_quantity': newQuantity,
        'last_updated': DateTime.now().toIso8601String(),
      },
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  /// ★ v6.31: 事务内安全扣减库存，防止负数 + 竞态条件
  /// 返回值：null = 扣减成功；int = 库存不足，值为当前库存量
  Future<int?> safeDecrementInventory(int productId, int quantity) async {
    final db = await database;
    int? currentStock;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT current_quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      if (result.isEmpty) {
        currentStock = 0;
        return;
      }
      final cur = (result.first['current_quantity'] as num).toInt();
      final newQty = cur - quantity;
      if (newQty < 0) {
        currentStock = cur;
        return; // ★ 库存不足，不更新，不截断
      }
      await txn.rawUpdate(
        'UPDATE inventory SET current_quantity = ?, last_updated = ? WHERE product_id = ?',
        [newQty, DateTime.now().toIso8601String(), productId],
      );
      currentStock = null; // null 表示成功
    });
    return currentStock;
  }

  /// 更新库存的最低预警阈值
  Future<int> updateInventoryMinStock(int productId, int minStockLevel) async {
    final db = await database;
    return await db.update(
      'inventory',
      {'min_stock_level': minStockLevel},
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  // ==================== STOCK RECORDS ====================

  Future<int> insertStockRecord(StockRecord record) async {
    final db = await database;
    return await db.insert('stock_records', record.toMap());
  }

  Future<List<StockRecord>> getStockRecords({
    StockType? type,
    DateTime? startDate,
    DateTime? endDate,
    String? barcode,
  }) async {
    final db = await database;
    final conditions = <String>['is_batch_internal = 0'];
    final args = <Object?>[];

    if (type != null) {
      conditions.add('type = ?');
      args.add(type.name);
    }
    if (startDate != null) {
      conditions.add('created_at >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      conditions.add('created_at <= ?');
      args.add(endDate.toIso8601String());
    }
    if (barcode != null) {
      conditions.add('barcode = ?');
      args.add(barcode);
    }

    final where = conditions.join(' AND ');
    final maps = await db.query(
      'stock_records',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => StockRecord.fromMap(m)).toList();
  }

  // ==================== ORDERS (v6.33) ====================

  /// 插入订单头
  Future<int> insertOrder(Order order) async {
    final db = await database;
    return await db.insert('orders', order.toMap());
  }

  /// 获取所有订单，按时间倒序
  Future<List<Order>> getOrders({int? limit}) async {
    final db = await database;
    final maps = await db.query(
      'orders',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => Order.fromMap(m)).toList();
  }

  /// 根据ID获取订单
  Future<Order?> getOrderById(int orderId) async {
    final db = await database;
    final maps = await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
    if (maps.isEmpty) return null;
    return Order.fromMap(maps.first);
  }

  /// 获取指定订单的出库记录
  Future<List<StockRecord>> getStockRecordsByOrderId(int orderId) async {
    final db = await database;
    final maps = await db.query(
      'stock_records',
      where: 'order_id = ? AND is_batch_internal = 0',
      whereArgs: [orderId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => StockRecord.fromMap(m)).toList();
  }

  /// 获取所有订单及其商品明细（用于历史查看）
  Future<List<Map<String, dynamic>>> getOrdersWithItems({int? limit}) async {
    final orders = await getOrders(limit: limit);
    final result = <Map<String, dynamic>>[];
    for (final o in orders) {
      final items = await getStockRecordsByOrderId(o.id!);
      result.add({'order': o, 'items': items});
    }
    return result;
  }

  /// 更新订单总额
  Future<void> updateOrderTotals(int orderId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(price_cny * quantity), 0) as total_cny,
             COALESCE(SUM(price_uzs * quantity), 0) as total_uzs
      FROM stock_records
      WHERE order_id = ? AND is_batch_internal = 0
    ''', [orderId]);
    if (result.isNotEmpty) {
      final cny = (result.first['total_cny'] as num).toDouble();
      final uzs = (result.first['total_uzs'] as num).toDouble();
      await db.update('orders', {
        'total_amount_cny': cny,
        'total_amount_uzs': uzs,
      }, where: 'id = ?', whereArgs: [orderId]);
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return await db.query(
      'stock_records',
      where: 'is_synced = 0 AND is_batch_internal = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<int> markRecordSynced(int id) async {
    final db = await database;
    return await db.update(
      'stock_records',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> isRecordSynced(int id) async {
    final db = await database;
    final result = await db.query(
      'stock_records',
      columns: ['is_synced'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return false;
    return (result.first['is_synced'] as int?) == 1;
  }

  // ==================== 单条记录详情查询 ====================

  /// 根据 ID 获取单条出入库记录（含商品名称），用于查看详情
  Future<Map<String, dynamic>?> getStockRecordById(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT sr.*, p.name_cn, p.name_ru, p.name_uz, p.category, p.unit
      FROM stock_records sr
      LEFT JOIN products p ON sr.product_id = p.id
      WHERE sr.id = ?
    ''', [id]);
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// 根据 ID 获取单条盘点任务（含操作人、筛选项等完整信息）
  Future<Map<String, dynamic>?> getCheckTaskDetailById(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT ct.*,
        (SELECT COUNT(*) FROM check_details cd WHERE cd.task_id = ct.id) as detail_count,
        (SELECT COUNT(*) FROM check_details cd WHERE cd.task_id = ct.id AND cd.difference != 0) as diff_count
      FROM check_tasks ct
      WHERE ct.id = ?
    ''', [id]);
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// 根据 ID 获取单条盘点明细（含商品名称）
  Future<Map<String, dynamic>?> getCheckDetailById(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT cd.*, p.name_cn, p.name_ru, p.name_uz, p.category, p.unit
      FROM check_details cd
      LEFT JOIN products p ON cd.product_id = p.id
      WHERE cd.id = ?
    ''', [id]);
    if (maps.isEmpty) return null;
    return maps.first;
  }

  // ==================== ENRICHED QUERIES (带商品名的查询) ====================

  /// 获取出入库记录（含商品名称），用于历史列表显示
  Future<List<Map<String, dynamic>>> getStockRecordsWithName({StockType? type}) async {
    final db = await database;
    String? where;
    List<Object?>? args;
    // v6.7: 过滤掉批次内部追踪记录，只显示主记录
    if (type != null) {
      where = 'sr.type = ? AND sr.is_batch_internal = 0';
      args = [type.name];
    } else {
      where = 'sr.is_batch_internal = 0';
    }
    final maps = await db.rawQuery('''
      SELECT sr.*, p.name_cn, p.name_ru, p.name_uz, p.unit_big, p.unit_small, p.unit_ratio
      FROM stock_records sr
      LEFT JOIN products p ON sr.product_id = p.id
      WHERE $where
      ORDER BY sr.created_at DESC
    ''', args);
    return maps;
  }

  /// FIFO 出库批次分配：按 expiry_date 从早到晚分配出库数量
  /// 返回每个批次的分配结果 [{expiry_date, quantity}]
  Future<List<Map<String, dynamic>>> allocateOutboundByFIFO(int productId, int quantity) async {
    final db = await database;
    if (quantity <= 0) return [];

    // 查询该商品所有有保质期的 inbound 批次，按 expiry_date 排序（先过期先出）
    final batches = await db.rawQuery('''
      SELECT sr.expiry_date,
             SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as net_qty
      FROM stock_records sr
      WHERE sr.product_id = ? AND sr.expiry_date IS NOT NULL
      GROUP BY sr.expiry_date
      HAVING net_qty > 0
      ORDER BY sr.expiry_date ASC
    ''', [productId]);

    final allocations = <Map<String, dynamic>>[];
    int remaining = quantity;

    for (final batch in batches) {
      if (remaining <= 0) break;
      final batchQty = (batch['net_qty'] as num).toInt();
      final deduct = remaining < batchQty ? remaining : batchQty;
      allocations.add({
        'expiry_date': batch['expiry_date'] as String,
        'quantity': deduct,
      });
      remaining -= deduct;
    }

    // 如果所有批次都不够，剩余数量分配为无 expiry_date 的出库
    if (remaining > 0) {
      allocations.add({
        'expiry_date': null,
        'quantity': remaining,
      });
    }

    return allocations;
  }

  /// 批次级别临期商品（基于stock_records批次数据，按expiry_date精确扣减）
  Future<List<Map<String, dynamic>>> getBatchNearExpiry() async {
    final db = await database;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final warn = DateTime(now.year, now.month, now.day + 30);
    final warnStr = '${warn.year}-${warn.month.toString().padLeft(2, '0')}-${warn.day.toString().padLeft(2, '0')}';
    return await db.rawQuery('''
      SELECT batch_data.product_id, batch_data.name_cn, batch_data.barcode,
             batch_data.category, batch_data.expiry_date,
             CAST(julianday(?) - julianday(date(batch_data.expiry_date)) AS INTEGER) as days_remaining,
             batch_data.net_qty as total_qty
      FROM (
        SELECT sr.product_id, p.name_cn, p.barcode, p.category,
               sr.expiry_date,
               SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as net_qty
        FROM stock_records sr
        INNER JOIN products p ON sr.product_id = p.id
        WHERE sr.expiry_date IS NOT NULL
        GROUP BY sr.product_id, sr.expiry_date
      ) batch_data
      INNER JOIN inventory i ON batch_data.product_id = i.product_id
      WHERE date(batch_data.expiry_date) >= ?
        AND date(batch_data.expiry_date) <= ?
        AND batch_data.net_qty > 0
        AND i.current_quantity > 0
      ORDER BY days_remaining ASC
    ''', [todayStr, todayStr, warnStr]);
  }

  /// 批次级别已过期商品（基于stock_records批次数据，按expiry_date精确扣减）
  Future<List<Map<String, dynamic>>> getBatchExpired() async {
    final db = await database;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return await db.rawQuery('''
      SELECT batch_data.product_id, batch_data.name_cn, batch_data.barcode,
             batch_data.category, batch_data.expiry_date,
             CAST(julianday(?) - julianday(date(batch_data.expiry_date)) AS INTEGER) as days_expired,
             batch_data.net_qty as total_qty
      FROM (
        SELECT sr.product_id, p.name_cn, p.barcode, p.category,
               sr.expiry_date,
               SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as net_qty
        FROM stock_records sr
        INNER JOIN products p ON sr.product_id = p.id
        WHERE sr.expiry_date IS NOT NULL
        GROUP BY sr.product_id, sr.expiry_date
      ) batch_data
      INNER JOIN inventory i ON batch_data.product_id = i.product_id
      WHERE date(batch_data.expiry_date) < ?
        AND batch_data.net_qty > 0
        AND i.current_quantity > 0
      ORDER BY days_expired DESC
    ''', [todayStr, todayStr]);
  }

  /// 低库存商品（含商品名称和预警线）
  Future<List<Map<String, dynamic>>> getLowStockWithName() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT i.*, p.name_cn, p.barcode, p.category, p.price_cny, p.price_uzs
      FROM inventory i
      INNER JOIN products p ON i.product_id = p.id
      WHERE i.current_quantity > 0
        AND i.current_quantity <= COALESCE(i.min_stock_level, 10)
      ORDER BY p.name_cn
    ''');
  }

  /// 获取单个商品的详细信息（用于商品详情弹窗）
  Future<Map<String, dynamic>?> getProductDetail(int productId) async {
    final db = await database;
    // 商品基本信息
    final products = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (products.isEmpty) return null;
    final product = products.first;

    // 库存信息
    final invList = await db.query('inventory', where: 'product_id = ?', whereArgs: [productId]);
    final totalStock = invList.fold<int>(0, (sum, i) => sum + ((i['current_quantity'] as num?)?.toInt() ?? 0));
    final minStock = invList.isNotEmpty ? (invList.first['min_stock_level'] as num?)?.toInt() ?? 10 : 10;

    // 批次级别保质期信息 (BUG 1 FIX: subtract outbound from inbound per batch)
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final batches = await db.rawQuery('''
      SELECT sr.expiry_date,
             SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as batch_qty,
             CAST(julianday(date(sr.expiry_date)) - julianday(?) AS INTEGER) as days_remaining
      FROM stock_records sr
      WHERE sr.product_id = ? AND sr.expiry_date IS NOT NULL
      GROUP BY sr.expiry_date
      HAVING batch_qty > 0
      ORDER BY sr.expiry_date ASC
    ''', [todayStr, productId]);

    return {
      ...product,
      'totalStock': totalStock,
      'minStock': minStock,
      'batches': batches,
    };
  }

  /// 根据ID获取商品名称
  Future<String?> getProductName(int productId) async {
    final db = await database;
    final result = await db.query('products',
        where: 'id = ?', whereArgs: [productId],
        columns: ['name_cn'], limit: 1);
    if (result.isEmpty) return null;
    return result.first['name_cn'] as String?;
  }

  /// 生成随机4位PIN码（★ v6.31: 改用安全随机数，不再基于时间戳）
  static String generatePin() {
    final random = Random.secure();
    return (1000 + random.nextInt(9000)).toString();
  }

  /// 更新用户PIN码（★ v6.31: 哈希存储）
  Future<int> updateUserPin(int userId, String pin) async {
    final db = await database;
    final salt = PasswordUtil.generateSalt();
    final hash = PasswordUtil.hashPassword(pin, salt);
    return await db.update('users', {
      'password_hash': hash,
      'password_salt': salt,
    }, where: 'id = ?', whereArgs: [userId]);
  }

  // ==================== CHECK TASKS ====================

  Future<int> insertCheckTask(CheckTask task) async {
    final db = await database;
    return await db.insert('check_tasks', task.toMap());
  }

  Future<int> updateCheckTask(CheckTask task) async {
    final db = await database;
    return await db.update(
      'check_tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// ★ v6.17: 删除盘点任务及关联明细
  Future<int> deleteCheckTask(int taskId) async {
    final db = await database;
    await db.delete('check_details', where: 'task_id = ?', whereArgs: [taskId]);
    return await db.delete('check_tasks', where: 'id = ?', whereArgs: [taskId]);
  }

  /// ★ v6.29: 标记盘点任务已被删除（防止云端同步重新下载）
  Future<void> markCheckTaskDeleted(String title, String operatorName) async {
    final db = await database;
    try {
      await db.insert('deleted_check_tasks', {
        'title': title,
        'operator_name': operatorName,
        'deleted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // 忽略重复插入
    }
  }

  /// ★ v6.29: 检查盘点任务是否已被用户删除
  Future<bool> isCheckTaskDeleted(String title, String operatorName) async {
    final db = await database;
    final result = await db.query(
      'deleted_check_tasks',
      where: 'title = ? AND operator_name = ?',
      whereArgs: [title, operatorName],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<CheckTask>> getCheckTasks({CheckTaskStatus? status}) async {
    final db = await database;
    String? where;
    List<Object?>? whereArgs;
    if (status != null) {
      where = 'status = ?';
      whereArgs = [status.name];
    }
    final maps = await db.query(
      'check_tasks',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => CheckTask.fromMap(m)).toList();
  }

  Future<CheckTask?> getCheckTaskById(int id) async {
    final db = await database;
    final maps = await db.query(
      'check_tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return CheckTask.fromMap(maps.first);
  }

  // ==================== CHECK DETAILS ====================

  Future<int> insertCheckDetail(CheckDetail detail) async {
    final db = await database;
    return await db.insert('check_details', detail.toMap());
  }

  Future<List<CheckDetail>> getCheckDetailsByTaskId(int taskId) async {
    final db = await database;
    final maps = await db.query(
      'check_details',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => CheckDetail.fromMap(m)).toList();
  }

  /// ★ v6.20: 删除指定任务的所有本地盘点明细（下载云端明细前清空，防止重复）
  Future<int> deleteCheckDetailsByTaskId(int taskId) async {
    final db = await database;
    return await db.delete(
      'check_details',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  Future<Map<String, dynamic>> getCheckSummary(int taskId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_items,
        SUM(CASE WHEN difference > 0 THEN 1 ELSE 0 END) as surplus_count,
        SUM(CASE WHEN difference < 0 THEN 1 ELSE 0 END) as shortage_count,
        SUM(CASE WHEN difference = 0 THEN 1 ELSE 0 END) as match_count,
        SUM(difference) as total_difference
      FROM check_details
      WHERE task_id = ?
    ''', [taskId]);
    return result.first;
  }

  /// 获取盘点详情（含商品名称）
  Future<List<Map<String, dynamic>>> getCheckDetailsWithNames(int taskId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT cd.*, p.name_cn, p.name_ru, p.name_uz, p.category
      FROM check_details cd
      LEFT JOIN products p ON cd.product_id = p.id
      WHERE cd.task_id = ?
      ORDER BY cd.created_at ASC
    ''', [taskId]);
  }

  // ==================== SHELVES ====================

  Future<int> insertShelf(Shelf shelf) async {
    final db = await database;
    return await db.insert('shelves', shelf.toMap());
  }

  Future<List<Shelf>> getAllShelves() async {
    final db = await database;
    final maps = await db.query('shelves', orderBy: 'code ASC');
    return maps.map((m) => Shelf.fromMap(m)).toList();
  }

  Future<int> insertShelfBinding(ShelfBinding binding) async {
    final db = await database;
    return await db.insert('shelf_bindings', binding.toMap());
  }

  Future<List<ShelfBinding>> getBindingsByShelfCode(String shelfCode) async {
    final db = await database;
    final maps = await db.query(
      'shelf_bindings',
      where: 'shelf_code = ?',
      whereArgs: [shelfCode],
    );
    return maps.map((m) => ShelfBinding.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getShelfWithProducts() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT sb.*, p.name_cn, p.name_ru, p.name_uz, p.barcode, p.category
      FROM shelf_bindings sb
      INNER JOIN products p ON sb.product_id = p.id
      ORDER BY sb.shelf_code, sb.row, sb.column
    ''');
  }

  /// ★ v6.27: 更新货架
  Future<int> updateShelf(Shelf shelf) async {
    final db = await database;
    return await db.update('shelves', shelf.toMap(),
        where: 'id = ?', whereArgs: [shelf.id]);
  }

  /// ★ v6.27: 删除货架
  Future<int> deleteShelf(int shelfId) async {
    final db = await database;
    return await db.delete('shelves', where: 'id = ?', whereArgs: [shelfId]);
  }

  /// ★ v6.30: 批量重命名区域内所有货架
  Future<int> batchRenameZone(String oldZone, String newZone) async {
    final db = await database;
    return await db.update('shelves', {'zone': newZone},
        where: 'zone = ?', whereArgs: [oldZone]);
  }

  /// ★ v6.30: 批量删除某区域下所有货架
  Future<int> deleteShelvesByZone(String zone) async {
    final db = await database;
    return await db.delete('shelves', where: 'zone = ?', whereArgs: [zone]);
  }

  /// ★ v6.31: 获取已入库但未定价/未上架的商品（库存>0）
  Future<List<Product>> getUnpricedProducts() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT p.* FROM products p
      INNER JOIN inventory i ON i.product_id = p.id
      WHERE i.current_quantity > 0
      ORDER BY p.name_cn
    ''');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  /// ★ v6.31: 更新商品进价+售价（含成本进价）
  Future<int> updateProductPrices(int productId, double priceCny, double priceUzs, {double costPriceCny = 0}) async {
    final db = await database;
    return await db.update('products', {
      'price_cny': priceCny,
      'price_uzs': priceUzs,
      'cost_price_cny': costPriceCny,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [productId]);
  }

  /// ★ v6.32: 更新商品分类名
  Future<int> updateProductCategory(int productId, String category) async {
    final db = await database;
    return await db.update('products', {
      'category': category,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [productId]);
  }

  /// ★ v6.32 (方案C): 按新汇率批量重算所有商品当地售价（price_uzs = price_cny × rate）
  /// 在用户切换国家时调用，确保所有商品的当地售价按最新汇率更新
  Future<int> recalcAllPriceUzs(double newRate) async {
    final db = await database;
    final affected = await db.rawUpdate('''
      UPDATE products
      SET price_uzs = ROUND(price_cny * ?, 2),
          updated_at = ?
      WHERE price_cny > 0
    ''', [newRate, DateTime.now().toIso8601String()]);
    print('[DB] recalcAllPriceUzs: rate=$newRate, affected=$affected');
    return affected;
  }

  /// ★ v6.31: 更新商品中文名（用于同步云端真实名称覆盖本地占位名称）
  Future<int> updateProductName(int productId, String nameCn) async {
    final db = await database;
    return await db.update('products', {
      'name_cn': nameCn,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [productId]);
  }

  /// ★ v6.31: 更新商品货架位置（同时更新 products 和 inventory 表）
  Future<int> updateProductShelf(int productId, String shelfLocation) async {
    final db = await database;
    // 1. 更新 products 表
    await db.update('products', {
      'shelf_location': shelfLocation,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [productId]);
    // 2. 同步更新 inventory 表（货架产品页按此查询）
    return await db.update('inventory', {
      'shelf_location': shelfLocation,
      'last_updated': DateTime.now().toIso8601String(),
    }, where: 'product_id = ?', whereArgs: [productId]);
  }

  /// ★ v6.30: 删除用户
  Future<int> deleteUser(int userId) async {
    final db = await database;
    return await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  /// ★ v6.30: 切换用户启用/停用
  Future<int> toggleUserActive(int userId, bool isActive) async {
    final db = await database;
    return await db.update('users', {'is_active': isActive ? 1 : 0},
        where: 'id = ?', whereArgs: [userId]);
  }

  /// ★ v6.27: 按 code 查找货架
  Future<Shelf?> getShelfByCode(String code) async {
    final db = await database;
    final maps = await db.query('shelves',
        where: 'code = ?', whereArgs: [code], limit: 1);
    if (maps.isEmpty) return null;
    return Shelf.fromMap(maps.first);
  }

  /// ★ v6.27: 获取库存>0的商品所在的货架列表（盘点规划用）
  Future<List<String>> getActiveShelfCodes() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT i.shelf_location FROM inventory i
      WHERE i.current_quantity > 0 AND i.shelf_location IS NOT NULL AND i.shelf_location != ''
      ORDER BY i.shelf_location
    ''');
    return result.map((r) => r['shelf_location'] as String).toList();
  }

  /// ★ v6.27: 获取盘点未覆盖的商品（全店库存>0 但不在指定条码列表中）
  Future<List<Map<String, dynamic>>> getUncheckedProducts(List<String> checkedBarcodes) async {
    final db = await database;
    if (checkedBarcodes.isEmpty) {
      return await db.rawQuery('''
        SELECT p.barcode, p.name_cn, p.category, i.current_quantity, i.shelf_location
        FROM inventory i
        INNER JOIN products p ON i.product_id = p.id
        WHERE i.current_quantity > 0
        ORDER BY p.category, p.name_cn
      ''');
    }
    final placeholders = checkedBarcodes.map((_) => '?').join(',');
    return await db.rawQuery('''
      SELECT p.barcode, p.name_cn, p.category, i.current_quantity, i.shelf_location
      FROM inventory i
      INNER JOIN products p ON i.product_id = p.id
      WHERE i.current_quantity > 0 AND p.barcode NOT IN ($placeholders)
      ORDER BY p.category, p.name_cn
    ''', checkedBarcodes);
  }

  /// ★ v6.27: 通用 rawQuery 委托（盘点规划等复杂查询用）
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? args]) async {
    final db = await database;
    return await db.rawQuery(sql, args);
  }

  // ==================== USERS ====================

  Future<int> insertUser(User user) async {
    final db = await database;
    return await db.insert('users', user.toMap());
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final maps = await db.query('users', orderBy: 'created_at DESC');
    return maps.map((m) => User.fromMap(m)).toList();
  }

  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return User.fromMap(maps.first);
  }

  /// ★ v6.31: 云端的哈希值更新到本地（云端同步用户时补充密码）
  Future<void> updateUserPassword(int userId, String passwordHash, String passwordSalt) async {
    final db = await database;
    await db.update(
      'users',
      {'password_hash': passwordHash, 'password_salt': passwordSalt},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<User?> loginUser(String username, String password) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'username = ? AND is_active = 1',
      whereArgs: [username],
      limit: 1,
    );
    if (maps.isEmpty) return null;

    final userData = maps.first;
    final storedHash = userData['password_hash'] as String?;
    final storedSalt = userData['password_salt'] as String?;

    if (storedHash == null || storedSalt == null) return null;
    if (!PasswordUtil.verify(password, storedSalt, storedHash)) return null;

    final user = User.fromMap(userData);
    await db.update(
      'users',
      {'last_login_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [user.id],
    );
    return user;
  }

  /// 手机号+验证码登录（验证码就是用户设置的PIN码）
  /// ★ v6.31: 哈希验证
  Future<User?> loginUserByPhone(String phone, String pin) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'phone = ? AND is_active = 1',
      whereArgs: [phone],
      limit: 1,
    );
    if (maps.isEmpty) return null;

    final userData = maps.first;
    final storedHash = userData['password_hash'] as String?;
    final storedSalt = userData['password_salt'] as String?;

    if (storedHash == null || storedSalt == null) return null;
    if (!PasswordUtil.verify(pin, storedSalt, storedHash)) return null;

    final user = User.fromMap(userData);
    await db.update(
      'users',
      {'last_login_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [user.id],
    );
    return user;
  }

  // ==================== OPERATION LOGS ====================

  Future<int> insertOperationLog(OperationLog log) async {
    final db = await database;
    return await db.insert('operation_logs', log.toMap());
  }

  Future<List<OperationLog>> getOperationLogs({
    String? username,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];

    if (username != null) {
      conditions.add('username = ?');
      args.add(username);
    }
    if (startDate != null) {
      conditions.add('created_at >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      conditions.add('created_at <= ?');
      args.add(endDate.toIso8601String());
    }

    final where = conditions.isEmpty ? null : conditions.join(' AND ');
    final maps = await db.query(
      'operation_logs',
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => OperationLog.fromMap(m)).toList();
  }

  // ==================== DASHBOARD STATS ====================

  /// 看板统计数据查询
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;
    final now = DateTime.now();
    final todayDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toIso8601String();

    // 计算+30天日期（处理跨月）
    final warningDate = DateTime(now.year, now.month, now.day + 30);
    final warningDateStr = '${warningDate.year}-${warningDate.month.toString().padLeft(2, '0')}-${warningDate.day.toString().padLeft(2, '0')}';

    int totalProducts = 0;
    int totalInventory = 0;
    int lowStockCount = 0;
    int todayInbound = 0;
    int todayOutbound = 0;
    int pendingChecks = 0;
    int nearExpiry = 0;
    int expired = 0;

    try {
      final r1 = await db.rawQuery('SELECT COUNT(DISTINCT product_id) as c FROM inventory WHERE current_quantity > 0');
      totalProducts = (r1.isNotEmpty ? r1.first['c'] as num? : 0)?.toInt() ?? 0;

      final r2 = await db.rawQuery('SELECT COALESCE(SUM(current_quantity), 0) as t FROM inventory');
      totalInventory = (r2.isNotEmpty ? r2.first['t'] as num? : 0)?.toInt() ?? 0;

      final r3 = await db.rawQuery("SELECT COUNT(*) as c FROM inventory WHERE current_quantity > 0 AND current_quantity <= COALESCE(min_stock_level, 10)");
      lowStockCount = (r3.isNotEmpty ? r3.first['c'] as num? : 0)?.toInt() ?? 0;

      final r4 = await db.rawQuery("SELECT COALESCE(SUM(quantity), 0) as t FROM stock_records WHERE type='inBound' AND is_batch_internal = 0 AND created_at>=? AND created_at<=?", [todayStart, todayEnd]);
      todayInbound = (r4.isNotEmpty ? r4.first['t'] as num? : 0)?.toInt() ?? 0;

      final r5 = await db.rawQuery("SELECT COALESCE(SUM(quantity), 0) as t FROM stock_records WHERE type='outBound' AND is_batch_internal = 0 AND created_at>=? AND created_at<=?", [todayStart, todayEnd]);
      todayOutbound = (r5.isNotEmpty ? r5.first['t'] as num? : 0)?.toInt() ?? 0;

      final r6 = await db.rawQuery("SELECT COUNT(*) as c FROM check_tasks WHERE status IN ('pending','inProgress')");
      pendingChecks = (r6.isNotEmpty ? r6.first['c'] as num? : 0)?.toInt() ?? 0;

      // 临期商品 = 按批次统计（按expiry_date精确扣减）
      final r7 = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM (
          SELECT sr.product_id, sr.expiry_date,
                 SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as net_qty
          FROM stock_records sr
          WHERE sr.expiry_date IS NOT NULL
          GROUP BY sr.product_id, sr.expiry_date
        ) batch_data
        INNER JOIN inventory i ON batch_data.product_id = i.product_id
        WHERE date(batch_data.expiry_date) >= ?
          AND date(batch_data.expiry_date) <= ?
          AND batch_data.net_qty > 0
          AND i.current_quantity > 0
      ''', [todayDateStr, warningDateStr]);
      nearExpiry = (r7.isNotEmpty ? r7.first['count'] as num? : 0)?.toInt() ?? 0;

      // 已过期商品 = 按批次统计（按expiry_date精确扣减）
      final r8 = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM (
          SELECT sr.product_id, sr.expiry_date,
                 SUM(CASE WHEN sr.type = 'inBound' THEN sr.quantity ELSE -sr.quantity END) as net_qty
          FROM stock_records sr
          WHERE sr.expiry_date IS NOT NULL
          GROUP BY sr.product_id, sr.expiry_date
        ) batch_data
        INNER JOIN inventory i ON batch_data.product_id = i.product_id
        WHERE date(batch_data.expiry_date) < ?
          AND batch_data.net_qty > 0
          AND i.current_quantity > 0
      ''', [todayDateStr]);
      expired = (r8.isNotEmpty ? r8.first['count'] as num? : 0)?.toInt() ?? 0;

    } catch (e) {
      // eslint-disable-next-line no-console
      print('[DashboardStats] Error: $e');
    }

    return {
      'totalProducts': totalProducts,
      'totalInventory': totalInventory,
      'lowStockCount': lowStockCount,
      'todayInbound': todayInbound,
      'todayOutbound': todayOutbound,
      'pendingChecks': pendingChecks,
      'nearExpiry': nearExpiry,
      'expired': expired,
    };
  }

  // ==================== SALES ANALYSIS ====================

  /// 按日期范围查询每日销售总额（出库且 outbound_reason = 'sale' 的记录）
  Future<List<Map<String, dynamic>>> getSalesByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    return await db.rawQuery('''
      SELECT date(sr.created_at) as sale_date,
             SUM(sr.quantity * sr.price_cny) as total_amount_cny,
             SUM(sr.quantity * sr.price_uzs) as total_amount_uzs,
             SUM(sr.quantity * sr.cost_price_cny) as total_cost_cny,
             SUM(sr.quantity * (sr.price_cny - COALESCE(sr.cost_price_cny, 0))) as profit_cny,
             SUM(sr.quantity) as total_quantity
      FROM stock_records sr
      WHERE sr.type = 'outBound'
        AND sr.outbound_reason = 'sale'
        AND sr.created_at >= ?
        AND sr.created_at <= ?
      GROUP BY date(sr.created_at)
      ORDER BY sale_date ASC
    ''', [startStr, endStr]);
  }

  /// 按商品分类查询销售总额
  Future<List<Map<String, dynamic>>> getSalesByCategory(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    return await db.rawQuery('''
      SELECT p.category,
             SUM(sr.quantity * sr.price_cny) as total_amount_cny,
             SUM(sr.quantity * sr.price_uzs) as total_amount_uzs,
             SUM(sr.quantity) as total_quantity
      FROM stock_records sr
      INNER JOIN products p ON sr.product_id = p.id
      WHERE sr.type = 'outBound'
        AND sr.outbound_reason = 'sale'
        AND sr.created_at >= ?
        AND sr.created_at <= ?
      GROUP BY p.category
      ORDER BY total_quantity DESC
    ''', [startStr, endStr]);
  }

  /// 查询销量排行前N的商品
  Future<List<Map<String, dynamic>>> getTopSellingProducts(DateTime start, DateTime end, {int limit = 10}) async {
    final db = await database;
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    return await db.rawQuery('''
      SELECT sr.product_id, p.name_cn, p.barcode, p.category,
             SUM(sr.quantity) as total_quantity,
             SUM(sr.quantity * sr.price_cny) as total_amount_cny,
             SUM(sr.quantity * sr.price_uzs) as total_amount_uzs
      FROM stock_records sr
      INNER JOIN products p ON sr.product_id = p.id
      WHERE sr.type = 'outBound'
        AND sr.outbound_reason = 'sale'
        AND sr.created_at >= ?
        AND sr.created_at <= ?
      GROUP BY sr.product_id
      ORDER BY total_quantity DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
  }

  /// 查询最近N个月的月度销售趋势
  Future<List<Map<String, dynamic>>> getMonthlySalesTrend(int months) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - months + 1, 1);
    final startStr = start.toIso8601String();
    return await db.rawQuery('''
      SELECT strftime('%Y-%m', sr.created_at) as month,
             SUM(sr.quantity * sr.price_cny) as total_amount_cny,
             SUM(sr.quantity * sr.price_uzs) as total_amount_uzs,
             SUM(sr.quantity * sr.cost_price_cny) as total_cost_cny,
             SUM(sr.quantity * (sr.price_cny - COALESCE(sr.cost_price_cny, 0))) as profit_cny,
             SUM(sr.quantity) as total_quantity
      FROM stock_records sr
      WHERE sr.type = 'outBound'
        AND sr.outbound_reason = 'sale'
        AND sr.created_at >= ?
      GROUP BY strftime('%Y-%m', sr.created_at)
      ORDER BY month ASC
    ''', [startStr]);
  }

  /// 查询最近N周的周度销售趋势
  Future<List<Map<String, dynamic>>> getWeeklySalesTrend(int weeks) async {
    final db = await database;
    final now = DateTime.now();
    final start = now.subtract(Duration(days: weeks * 7));
    final startStr = start.toIso8601String();
    return await db.rawQuery('''
      SELECT strftime('%Y-W%W', sr.created_at) as week,
             SUM(sr.quantity * sr.price_cny) as total_amount_cny,
             SUM(sr.quantity * sr.price_uzs) as total_amount_uzs,
             SUM(sr.quantity * sr.cost_price_cny) as total_cost_cny,
             SUM(sr.quantity * (sr.price_cny - COALESCE(sr.cost_price_cny, 0))) as profit_cny,
             SUM(sr.quantity) as total_quantity
      FROM stock_records sr
      WHERE sr.type = 'outBound'
        AND sr.outbound_reason = 'sale'
        AND sr.created_at >= ?
      GROUP BY strftime('%Y-W%W', sr.created_at)
      ORDER BY week ASC
    ''', [startStr]);
  }

  // ==================== BIDIRECTIONAL SYNC ====================

  /// 获取所有未同步的出入库记录（is_synced = 0）
  Future<List<Map<String, dynamic>>> getUnsyncedStockRecords() async {
    final db = await database;
    return await db.query(
      'stock_records',
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  /// 从云端插入一条出入库记录（显式设置 is_synced = 1 避免重复上传）
  ///
  /// ★ v6.2 修复根因⑤：原 insertStockRecord 用 record.toMap()，
  /// 若 StockRecord.toMap() 不含 is_synced 字段，落库后默认 0，
  /// 下载来的流水会被下一轮 uploadPendingStockRecords 当未同步记录重新上传 → 翻倍。
  /// 此方法接收 StockRecord 对象，在 toMap() 基础上显式覆盖 is_synced = 1。
  Future<int> insertStockRecordFromCloud(StockRecord record) async {
    final db = await database;
    final map = record.toMap();
    // ★ 显式覆盖 is_synced = 1，不依赖 toMap() 是否包含该字段
    map['is_synced'] = 1;
    // 移除 id，让 SQLite 自增
    map.remove('id');
    return await db.insert('stock_records', map);
  }

  /// ★ v6.2 新增：检查某条云端流水是否已被本设备处理过（幂等查重）
  /// 用于 downloadStockRecords 避免重复应用同一条云端流水
  /// ★ v6.4 修复：cloudId 改为 String，兼容 UUID 和整数 ID
  Future<bool> isCloudRecordSynced(String cloudId, {String tableName = 'stock_records_cloud'}) async {
    final db = await database;
    final result = await db.query(
      'synced_cloud_records',
      where: 'cloud_id = ? AND table_name = ?',
      whereArgs: [cloudId, tableName],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// ★ v6.2 新增：标记某条云端流水为已处理（幂等）
  /// 处理完一条云端流水后调用，下次下载时跳过
  /// ★ v6.4 修复：cloudId 改为 String，兼容 UUID 和整数 ID
  Future<void> markCloudRecordSynced(String cloudId, {String tableName = 'stock_records_cloud', int? localRecordId}) async {
    final db = await database;
    try {
      await db.insert(
        'synced_cloud_records',
        {
          'cloud_id': cloudId,
          'table_name': tableName,
          'local_record_id': localRecordId,
          'synced_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // 主键冲突表示已标记过，忽略
    }
  }

  /// 获取所有盘点任务（用于同步上传）
  Future<List<Map<String, dynamic>>> getCheckTasksForSync() async {
    final db = await database;
    return await db.query(
      'check_tasks',
      orderBy: 'created_at ASC',
    );
  }

  /// 获取指定盘点任务的所有盘点明细（用于同步上传）
  Future<List<Map<String, dynamic>>> getCheckDetailsForTask(int taskId) async {
    final db = await database;
    return await db.query(
      'check_details',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    );
  }

  /// 从云端插入一条盘点任务
  Future<int> insertCheckTaskFromCloud(Map<String, dynamic> data) async {
    final db = await database;
    final record = Map<String, dynamic>.from(data);
    // Remove 'id' if present to let auto-increment work
    record.remove('id');
    return await db.insert('check_tasks', record);
  }

  /// 从云端插入一条盘点明细
  Future<int> insertCheckDetailFromCloud(Map<String, dynamic> data) async {
    final db = await database;
    final record = Map<String, dynamic>.from(data);
    // Remove 'id' if present to let auto-increment work
    record.remove('id');
    return await db.insert('check_details', record);
  }

  /// 获取最近一条已同步出入库记录的 created_at（用于增量下载）
  Future<String?> getLatestStockRecordTime() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT created_at FROM stock_records
      WHERE is_synced = 1
      ORDER BY created_at DESC
      LIMIT 1
    ''');
    if (result.isEmpty) return null;
    return result.first['created_at'] as String?;
  }

  // ==================== CLEANUP ====================

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
