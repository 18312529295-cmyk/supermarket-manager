enum StockType { inBound, outBound }

enum OutboundReason { sale, loss, damage, expiry, returnToSupplier, other }

extension OutboundReasonExtension on OutboundReason {
  String get displayName {
    switch (this) {
      case OutboundReason.sale:
        return '销售出库';
      case OutboundReason.loss:
        return '损耗出库';
      case OutboundReason.damage:
        return '破损出库';
      case OutboundReason.expiry:
        return '过期出库';
      case OutboundReason.returnToSupplier:
        return '退货出库';
      case OutboundReason.other:
        return '其他';
    }
  }
}

class StockRecord {
  final int? id;
  final int productId;
  final String barcode;
  final StockType type;
  final int quantity;
  final double priceCny;
  final double priceUzs;
  final double costPriceCny;
  final OutboundReason? outboundReason;
  final String? destination;
  final String? supplier;
  final String? batchNumber;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final String operatorName;
  final String? note;
  final bool isSynced;
  final bool isBatchInternal;
  final DateTime createdAt;

  StockRecord({
    this.id,
    required this.productId,
    required this.barcode,
    required this.type,
    required this.quantity,
    required this.priceCny,
    required this.priceUzs,
    this.costPriceCny = 0,
    this.outboundReason,
    this.destination,
    this.supplier,
    this.batchNumber,
    this.productionDate,
    this.expiryDate,
    required this.operatorName,
    this.note,
    this.isSynced = false,
    this.isBatchInternal = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'barcode': barcode,
      'type': type.name,
      'quantity': quantity,
      'price_cny': priceCny,
      'price_uzs': priceUzs,
      'cost_price_cny': costPriceCny,
      'outbound_reason': outboundReason?.name,
      'destination': destination,
      'supplier': supplier,
      'batch_number': batchNumber,
      'production_date': productionDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'operator_name': operatorName,
      'note': note,
      'is_synced': isSynced ? 1 : 0,
      'is_batch_internal': isBatchInternal ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockRecord.fromMap(Map<String, dynamic> map) {
    return StockRecord(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      barcode: map['barcode'] as String,
      type: StockType.values.byName(map['type'] as String),
      quantity: map['quantity'] as int,
      priceCny: (map['price_cny'] as num).toDouble(),
      priceUzs: (map['price_uzs'] as num).toDouble(),
      costPriceCny: (map['cost_price_cny'] as num?)?.toDouble() ?? 0,
      outboundReason: map['outbound_reason'] != null
          ? OutboundReason.values.byName(map['outbound_reason'] as String)
          : null,
      destination: map['destination'] as String?,
      supplier: map['supplier'] as String?,
      batchNumber: map['batch_number'] as String?,
      productionDate: map['production_date'] != null
          ? DateTime.parse(map['production_date'] as String)
          : null,
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      operatorName: map['operator_name'] as String,
      note: map['note'] as String?,
      isSynced: map['is_synced'] == 1,
      isBatchInternal: map['is_batch_internal'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  double get totalCny => priceCny * quantity;
  double get totalUzs => priceUzs * quantity;

  StockRecord copyWith({
    int? id,
    int? productId,
    String? barcode,
    StockType? type,
    int? quantity,
    double? priceCny,
    double? priceUzs,
    double? costPriceCny,
    OutboundReason? outboundReason,
    String? destination,
    String? supplier,
    String? batchNumber,
    DateTime? productionDate,
    DateTime? expiryDate,
    String? operatorName,
    String? note,
    bool? isSynced,
    bool? isBatchInternal,
    DateTime? createdAt,
  }) {
    return StockRecord(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      barcode: barcode ?? this.barcode,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      priceCny: priceCny ?? this.priceCny,
      priceUzs: priceUzs ?? this.priceUzs,
      costPriceCny: costPriceCny ?? this.costPriceCny,
      outboundReason: outboundReason ?? this.outboundReason,
      destination: destination ?? this.destination,
      supplier: supplier ?? this.supplier,
      batchNumber: batchNumber ?? this.batchNumber,
      productionDate: productionDate ?? this.productionDate,
      expiryDate: expiryDate ?? this.expiryDate,
      operatorName: operatorName ?? this.operatorName,
      note: note ?? this.note,
      isSynced: isSynced ?? this.isSynced,
      isBatchInternal: isBatchInternal ?? this.isBatchInternal,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
