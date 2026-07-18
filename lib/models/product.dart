class Product {
  final int? id;
  final String barcode;
  final String nameCn;
  final String? nameRu;
  final String? nameUz;
  /// ★ v6.30: 外语名称（合并俄语和乌兹别克语）
  final String? foreignName;
  final String category;
  final String? shelfLocation;
  final double priceCny;
  final double priceUzs;
  /// ★ v6.31: 成本进价（人民币）
  final double costPriceCny;
  final String? unit;
  final String? supplier;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final int shelfLifeDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ★ 复合单位支持
  final String? unitBig;
  final String? unitSmall;
  final int? unitRatio;

  Product({
    this.id,
    required this.barcode,
    required this.nameCn,
    this.nameRu,
    this.nameUz,
    this.foreignName,
    required this.category,
    this.shelfLocation,
    required this.priceCny,
    required this.priceUzs,
    this.costPriceCny = 0,
    this.unit,
    this.supplier,
    this.productionDate,
    this.expiryDate,
    this.shelfLifeDays = 0,
    this.unitBig,
    this.unitSmall,
    this.unitRatio,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name_cn': nameCn,
      'name_ru': nameRu,
      'name_uz': nameUz,
      'foreign_name': foreignName,
      'category': category,
      'shelf_location': shelfLocation,
      'price_cny': priceCny,
      'price_uzs': priceUzs,
      'cost_price_cny': costPriceCny,
      'unit': unit,
      'supplier': supplier,
      'production_date': productionDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'shelf_life_days': shelfLifeDays,
      'unit_big': unitBig,
      'unit_small': unitSmall,
      'unit_ratio': unitRatio,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      nameCn: map['name_cn'] as String,
      nameRu: map['name_ru'] as String?,
      nameUz: map['name_uz'] as String?,
      foreignName: map['foreign_name'] as String?,
      category: map['category'] as String,
      shelfLocation: map['shelf_location'] as String?,
      priceCny: (map['price_cny'] as num).toDouble(),
      priceUzs: (map['price_uzs'] as num).toDouble(),
      costPriceCny: (map['cost_price_cny'] as num? ?? 0).toDouble(),
      unit: map['unit'] as String?,
      supplier: map['supplier'] as String?,
      productionDate: map['production_date'] != null
          ? DateTime.parse(map['production_date'] as String)
          : null,
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      shelfLifeDays: map['shelf_life_days'] as int? ?? 0,
      unitBig: map['unit_big'] as String?,
      unitSmall: map['unit_small'] as String?,
      unitRatio: map['unit_ratio'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? nameCn,
    String? nameRu,
    String? nameUz,
    String? foreignName,
    String? category,
    String? shelfLocation,
    double? priceCny,
    double? priceUzs,
    double? costPriceCny,
    String? unit,
    String? supplier,
    DateTime? productionDate,
    DateTime? expiryDate,
    int? shelfLifeDays,
    String? unitBig,
    String? unitSmall,
    int? unitRatio,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      nameCn: nameCn ?? this.nameCn,
      nameRu: nameRu ?? this.nameRu,
      nameUz: nameUz ?? this.nameUz,
      foreignName: foreignName ?? this.foreignName,
      category: category ?? this.category,
      shelfLocation: shelfLocation ?? this.shelfLocation,
      priceCny: priceCny ?? this.priceCny,
      priceUzs: priceUzs ?? this.priceUzs,
      costPriceCny: costPriceCny ?? this.costPriceCny,
      unit: unit ?? this.unit,
      supplier: supplier ?? this.supplier,
      productionDate: productionDate ?? this.productionDate,
      expiryDate: expiryDate ?? this.expiryDate,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
      unitBig: unitBig ?? this.unitBig,
      unitSmall: unitSmall ?? this.unitSmall,
      unitRatio: unitRatio ?? this.unitRatio,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String formatCompositeQty(int totalSmallQty) {
    if (unitBig != null && unitSmall != null && unitRatio != null && unitRatio! > 0) {
      final big = totalSmallQty ~/ unitRatio!;
      final small = totalSmallQty % unitRatio!;
      if (big > 0) {
        return small > 0 ? '$big$unitBig$small$unitSmall' : '$big$unitBig';
      }
      return '$small$unitSmall';
    }
    return '$totalSmallQty${unit ?? "件"}';
  }

  String formatCompositeQtyDetail(int totalSmallQty) {
    if (unitBig != null && unitSmall != null && unitRatio != null && unitRatio! > 0) {
      final big = totalSmallQty ~/ unitRatio!;
      final small = totalSmallQty % unitRatio!;
      if (big > 0) {
        if (small > 0) {
          return '$big$unitBig$small$unitSmall（共${totalSmallQty}$unitSmall）';
        }
        return '$big$unitBig（共${totalSmallQty}$unitSmall）';
      }
      return '$small$unitSmall';
    }
    return '$totalSmallQty${unit ?? "件"}';
  }

  /// ★ v6.31: 静态方法，用于从DB字段直接格式化复合数量（含总量）
  static String formatCompositeQtyStatic(int totalSmallQty, String unitBig, String unitSmall, int unitRatio) {
    final big = totalSmallQty ~/ unitRatio;
    final small = totalSmallQty % unitRatio;
    if (big > 0) {
      return small > 0 ? '+$big$unitBig$small$unitSmall（共$totalSmallQty$unitSmall）' : '+$big$unitBig（共$totalSmallQty$unitSmall）';
    }
    return '+$small$unitSmall';
  }

  int toTotalSmallQty(int bigQty, int smallQty) {
    if (unitRatio != null && unitRatio! > 0) {
      return bigQty * unitRatio! + smallQty;
    }
    return bigQty + smallQty;
  }

  /// ★ v6.30: getDisplayName 优先使用 foreignName
  String getDisplayName(String langCode) {
    if (foreignName != null && foreignName!.isNotEmpty && langCode != 'zh') {
      return foreignName!;
    }
    switch (langCode) {
      case 'ru':
        return nameRu ?? foreignName ?? nameCn;
      case 'uz':
        return nameUz ?? foreignName ?? nameCn;
      case 'zh':
      default:
        return nameCn;
    }
  }

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get isNearExpiry {
    if (expiryDate == null) return false;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= 7;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }
}
