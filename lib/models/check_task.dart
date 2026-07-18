import 'package:flutter/material.dart';

enum CheckTaskStatus { pending, inProgress, completed, cancelled }

extension CheckTaskStatusExtension on CheckTaskStatus {
  String get displayName {
    switch (this) {
      case CheckTaskStatus.pending:
        return '待盘点';
      case CheckTaskStatus.inProgress:
        return '盘点中';
      case CheckTaskStatus.completed:
        return '已完成';
      case CheckTaskStatus.cancelled:
        return '已取消';
    }
  }

  Color get color {
    switch (this) {
      case CheckTaskStatus.pending:
        return Colors.orange;
      case CheckTaskStatus.inProgress:
        return Colors.blue;
      case CheckTaskStatus.completed:
        return Colors.green;
      case CheckTaskStatus.cancelled:
        return Colors.grey;
    }
  }
}

class CheckTask {
  final int? id;
  final String title;
  final CheckTaskStatus status;
  final String? categoryFilter;
  final String? shelfFilter;
  final String operatorName;
  final int totalItems;
  final int checkedItems;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final String? assignedTo;  // ★ v6.16: 分配给哪个操作人（店长分配盘点任务）

  CheckTask({
    this.id,
    required this.title,
    this.status = CheckTaskStatus.pending,
    this.categoryFilter,
    this.shelfFilter,
    required this.operatorName,
    this.totalItems = 0,
    this.checkedItems = 0,
    this.startedAt,
    this.completedAt,
    DateTime? createdAt,
    this.assignedTo,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'status': status.name,
      'category_filter': categoryFilter,
      'shelf_filter': shelfFilter,
      'operator_name': operatorName,
      'total_items': totalItems,
      'checked_items': checkedItems,
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'assigned_to': assignedTo,
    };
  }

  factory CheckTask.fromMap(Map<String, dynamic> map) {
    return CheckTask(
      id: map['id'] as int?,
      title: map['title'] as String,
      status: CheckTaskStatus.values.byName(map['status'] as String),
      categoryFilter: map['category_filter'] as String?,
      shelfFilter: map['shelf_filter'] as String?,
      operatorName: map['operator_name'] as String,
      totalItems: map['total_items'] as int,
      checkedItems: map['checked_items'] as int,
      startedAt: map['started_at'] != null
          ? DateTime.parse(map['started_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      assignedTo: map['assigned_to'] as String?,
    );
  }

  CheckTask copyWith({
    int? id,
    String? title,
    CheckTaskStatus? status,
    String? categoryFilter,
    String? shelfFilter,
    String? operatorName,
    int? totalItems,
    int? checkedItems,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    String? assignedTo,
  }) {
    return CheckTask(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      shelfFilter: shelfFilter ?? this.shelfFilter,
      operatorName: operatorName ?? this.operatorName,
      totalItems: totalItems ?? this.totalItems,
      checkedItems: checkedItems ?? this.checkedItems,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      assignedTo: assignedTo ?? this.assignedTo,
    );
  }

  double get progress =>
      totalItems > 0 ? checkedItems / totalItems : 0.0;
}

class CheckDetail {
  final int? id;
  final int taskId;
  final int productId;
  final String barcode;
  final int systemQuantity;
  final int actualQuantity;
  final int difference;
  final String? note;
  final int? actualExpiredQty;
  final int? actualNearExpiryQty;
  final String? shelfLocation;
  final DateTime createdAt;

  CheckDetail({
    this.id,
    required this.taskId,
    required this.productId,
    required this.barcode,
    required this.systemQuantity,
    required this.actualQuantity,
    required this.difference,
    this.note,
    this.actualExpiredQty,
    this.actualNearExpiryQty,
    this.shelfLocation,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'product_id': productId,
      'barcode': barcode,
      'system_quantity': systemQuantity,
      'actual_quantity': actualQuantity,
      'difference': difference,
      'note': note,
      'actual_expired_qty': actualExpiredQty,
      'actual_near_expiry_qty': actualNearExpiryQty,
      'shelf_location': shelfLocation,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CheckDetail.fromMap(Map<String, dynamic> map) {
    return CheckDetail(
      id: map['id'] as int?,
      taskId: map['task_id'] as int,
      productId: map['product_id'] as int,
      barcode: map['barcode'] as String,
      systemQuantity: map['system_quantity'] as int,
      actualQuantity: map['actual_quantity'] as int,
      difference: map['difference'] as int,
      note: map['note'] as String?,
      actualExpiredQty: map['actual_expired_qty'] as int?,
      actualNearExpiryQty: map['actual_near_expiry_qty'] as int?,
      shelfLocation: map['shelf_location'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  bool get isSurplus => difference > 0;
  bool get isShortage => difference < 0;
}
