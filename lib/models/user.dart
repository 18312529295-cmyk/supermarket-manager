enum UserRole { admin, manager, cashier, stockKeeper }

extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.admin:
        return '管理员';
      case UserRole.manager:
        return '店长';
      case UserRole.cashier:
        return '收银员';
      case UserRole.stockKeeper:
        return '仓管员';
    }
  }

  /// ★ v6.30: manager(店长)也可以管理用户
  bool get canManageUsers => this == UserRole.admin || this == UserRole.manager;
  bool get canEditInventory => this == UserRole.admin || this == UserRole.manager || this == UserRole.stockKeeper;
  bool get canViewReports => this == UserRole.admin || this == UserRole.manager;
  bool get canManageShelf => this == UserRole.admin || this == UserRole.manager || this == UserRole.stockKeeper;
}

class User {
  final int? id;
  final String username;
  final String displayName;
  /// ★ v6.31: 改为哈希存储，不再存明文密码
  final String? passwordHash;
  final String? passwordSalt;
  final UserRole role;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  User({
    this.id,
    required this.username,
    required this.displayName,
    this.passwordHash,
    this.passwordSalt,
    required this.role,
    this.phone,
    this.isActive = true,
    DateTime? createdAt,
    this.lastLoginAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (passwordSalt != null) 'password_salt': passwordSalt,
      'role': role.name,
      'phone': phone,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      username: map['username'] as String,
      displayName: map['display_name'] as String,
      passwordHash: map['password_hash'] as String?,
      passwordSalt: map['password_salt'] as String?,
      role: UserRole.values.byName(map['role'] as String),
      phone: map['phone'] as String?,
      isActive: map['is_active'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.parse(map['last_login_at'] as String)
          : null,
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? displayName,
    String? passwordHash,
    String? passwordSalt,
    UserRole? role,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

class OperationLog {
  final int? id;
  final int? userId;
  final String username;
  final String action;
  final String? detail;
  final String? barcode;
  final DateTime createdAt;

  OperationLog({
    this.id,
    this.userId,
    required this.username,
    required this.action,
    this.detail,
    this.barcode,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'action': action,
      'detail': detail,
      'barcode': barcode,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory OperationLog.fromMap(Map<String, dynamic> map) {
    return OperationLog(
      id: map['id'] as int?,
      userId: map['user_id'] as int?,
      username: map['username'] as String,
      action: map['action'] as String,
      detail: map['detail'] as String?,
      barcode: map['barcode'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
