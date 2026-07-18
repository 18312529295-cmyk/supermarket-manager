class Shelf {
  final int? id;
  final String code;
  final String name;
  final String zone;
  final String? description;
  final DateTime createdAt;

  Shelf({
    this.id,
    required this.code,
    required this.name,
    required this.zone,
    this.description,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'zone': zone,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Shelf.fromMap(Map<String, dynamic> map) {
    return Shelf(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String,
      zone: map['zone'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Shelf copyWith({
    int? id,
    String? code,
    String? name,
    String? zone,
    String? description,
    DateTime? createdAt,
  }) {
    return Shelf(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      zone: zone ?? this.zone,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ShelfBinding {
  final int? id;
  final int productId;
  final String shelfCode;
  final int? row;
  final int? column;
  final String? note;
  final DateTime createdAt;

  ShelfBinding({
    this.id,
    required this.productId,
    required this.shelfCode,
    this.row,
    this.column,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'shelf_code': shelfCode,
      'row': row,
      'column': column,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ShelfBinding.fromMap(Map<String, dynamic> map) {
    return ShelfBinding(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      shelfCode: map['shelf_code'] as String,
      row: map['row'] as int?,
      column: map['column'] as int?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  String get locationText {
    if (row != null && column != null) {
      return '$shelfCode - ${row}排${column}列';
    }
    return shelfCode;
  }
}
