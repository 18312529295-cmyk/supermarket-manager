/// v6.33: 订单/交易头
class Order {
  final int? id;
  final String customerName;       // 客户名
  final double totalAmountCny;     // 总价(人民币)
  final double totalAmountUzs;     // 总价(当地货币)
  final String operatorName;       // 操作人
  final String? note;              // 备注
  final bool isSynced;
  final DateTime createdAt;

  Order({
    this.id,
    required this.customerName,
    this.totalAmountCny = 0,
    this.totalAmountUzs = 0,
    required this.operatorName,
    this.note,
    this.isSynced = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'total_amount_cny': totalAmountCny,
      'total_amount_uzs': totalAmountUzs,
      'operator_name': operatorName,
      'note': note,
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as int?,
      customerName: map['customer_name'] as String,
      totalAmountCny: (map['total_amount_cny'] as num).toDouble(),
      totalAmountUzs: (map['total_amount_uzs'] as num).toDouble(),
      operatorName: map['operator_name'] as String,
      note: map['note'] as String?,
      isSynced: map['is_synced'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Order copyWith({
    int? id,
    String? customerName,
    double? totalAmountCny,
    double? totalAmountUzs,
    String? operatorName,
    String? note,
    bool? isSynced,
    DateTime? createdAt,
  }) {
    return Order(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      totalAmountCny: totalAmountCny ?? this.totalAmountCny,
      totalAmountUzs: totalAmountUzs ?? this.totalAmountUzs,
      operatorName: operatorName ?? this.operatorName,
      note: note ?? this.note,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
