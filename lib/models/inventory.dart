class Inventory {
  final int? id;
  final int productId;
  final String barcode;
  final int currentQuantity;
  final int? minStockLevel;
  final String? shelfLocation;
  final DateTime lastUpdated;
  final DateTime? lastCheckedAt;
  final int? checkedQuantity;

  Inventory({
    this.id,
    required this.productId,
    required this.barcode,
    required this.currentQuantity,
    this.minStockLevel,
    this.shelfLocation,
    DateTime? lastUpdated,
    this.lastCheckedAt,
    this.checkedQuantity,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'barcode': barcode,
      'current_quantity': currentQuantity,
      'min_stock_level': minStockLevel,
      'shelf_location': shelfLocation,
      'last_updated': lastUpdated.toIso8601String(),
      'last_checked_at': lastCheckedAt?.toIso8601String(),
      'checked_quantity': checkedQuantity,
    };
  }

  factory Inventory.fromMap(Map<String, dynamic> map) {
    return Inventory(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      barcode: map['barcode'] as String,
      currentQuantity: map['current_quantity'] as int,
      minStockLevel: map['min_stock_level'] as int?,
      shelfLocation: map['shelf_location'] as String?,
      lastUpdated: DateTime.parse(map['last_updated'] as String),
      lastCheckedAt: map['last_checked_at'] != null
          ? DateTime.parse(map['last_checked_at'] as String)
          : null,
      checkedQuantity: map['checked_quantity'] as int?,
    );
  }

  Inventory copyWith({
    int? id,
    int? productId,
    String? barcode,
    int? currentQuantity,
    int? minStockLevel,
    String? shelfLocation,
    DateTime? lastUpdated,
    DateTime? lastCheckedAt,
    int? checkedQuantity,
  }) {
    return Inventory(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      barcode: barcode ?? this.barcode,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      shelfLocation: shelfLocation ?? this.shelfLocation,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      checkedQuantity: checkedQuantity ?? this.checkedQuantity,
    );
  }

  bool get isLowStock {
    if (minStockLevel == null) return false;
    return currentQuantity <= minStockLevel!;
  }

  int? get difference =>
      checkedQuantity != null ? checkedQuantity! - currentQuantity : null;
}
