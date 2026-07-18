import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as local_user;
import '../services/supabase_sync_service.dart';  // ★ v6.3
import '../services/database_service.dart';  // ★ v6.32
import '../config/country_config.dart';  // ★ v6.30
import '../config/supabase_config.dart';  // ★ v6.31

class AppProvider extends ChangeNotifier {
  String _languageCode = 'zh';
  String get languageCode => _languageCode;

  String _currencyDisplay = 'both'; // 'cny', 'uzs', 'both'
  String get currencyDisplay => _currencyDisplay;

  /// ★ v6.30: 当前选中国家
  String _countryCode = 'CN';
  String get countryCode => _countryCode;

  CountryConfig get countryConfig => CountryConfig.fromCode(_countryCode);

  String _currentUser = '';
  String get currentUser => _currentUser;

  String _currentUsername = '';
  /// ★ v6.26: username 用于盘点任务分配匹配（displayName 和 username 可能不同）
  String get currentUsername => _currentUsername;

  local_user.UserRole? _currentUserRole;
  local_user.UserRole? get currentUserRole => _currentUserRole;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  int _pendingSyncCount = 0;
  int get pendingSyncCount => _pendingSyncCount;

  String _storeName = '';
  String get storeName => _storeName;

  /// ★ v6.3: 当前超市ID（动态，支持多店区分）
  /// 默认 'main' 兼容老数据；新超市注册时生成唯一 store_id
  String _storeId = 'main';
  String get storeId => _storeId;

  AppProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString('language_code') ?? 'zh';
    _currencyDisplay = prefs.getString('currency_display') ?? 'both';
    _currentUser = prefs.getString('current_user') ?? '';
    _currentUsername = prefs.getString('current_user_username') ?? '';
    _storeName = prefs.getString('store_name') ?? '';
    _storeId = prefs.getString('store_id') ?? 'main';  // ★ v6.3
    final roleStr = prefs.getString('current_user_role');
    if (roleStr != null) {
      try {
        _currentUserRole = local_user.UserRole.values.byName(roleStr);
      } catch (_) {
        _currentUserRole = null;
      }
    }
    _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    _countryCode = prefs.getString('country_code') ?? 'CN';
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    notifyListeners();
  }

  Future<void> setCurrencyDisplay(String display) async {
    _currencyDisplay = display;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency_display', display);
    notifyListeners();
  }

  /// ★ v6.30: 设置国家（联动语言 + 货币）
  Future<void> setCountry(String code) async {
    if (_countryCode == code) return;
    _countryCode = code;
    final cfg = CountryConfig.fromCode(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('country_code', code);
    await prefs.setString('language_code', cfg.langCode);
    _languageCode = cfg.langCode;
    // 默认切换到双币显示
    await prefs.setString('currency_display', 'both');
    _currencyDisplay = 'both';
    notifyListeners();
  }

  /// ★ v6.32: 按当前国家汇率批量重算所有商品当地售价
  /// 独立方法，可在同步后强制调用，不受 setCountry 的 return 阻断
  Future<void> forceRecalcPrices() async {
    final cfg = CountryConfig.fromCode(_countryCode);
    try {
      final db = DatabaseService.instance;
      await db.recalcAllPriceUzs(cfg.cnyExchangeRate);
      debugPrint('[AppProvider] forceRecalcPrices: rate=${cfg.cnyExchangeRate}');
    } catch (e) {
      debugPrint('[AppProvider] forceRecalcPrices error: $e');
    }
  }

  Future<void> login(local_user.User user, {String? password}) async {
    _currentUser = user.displayName;
    _currentUsername = user.username;
    _currentUserRole = user.role;
    _isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user', user.displayName);
    await prefs.setString('current_user_role', user.role.name);
    await prefs.setString('current_user_username', user.username);
    await prefs.setBool('is_logged_in', true);

    // ★ v6.31: 同时登录 Supabase Auth（失败不阻断本地登录）
    if (password != null && password.isNotEmpty) {
      await _ensureSupabaseAuth(user, password);
    }

    notifyListeners();
  }

  /// ★ v6.31: 确保该用户在 Supabase Auth 中存在并登录
  /// 失败不阻断本地登录，但会打印详细日志
  Future<void> _ensureSupabaseAuth(local_user.User user, String password) async {
    final supabase = Supabase.instance.client;
    final email = SupabaseConfig.authEmail(phone: user.phone, username: user.username);

    // Supabase Auth 要求密码至少 6 位；PIN 不足时补零，不影响用户侧 PIN
    final effectivePassword = password.length >= 6 ? password : password.padRight(6, '0');

    // 从 prefs 读取最新 store_id（防止初始化向导刚写入但 AppProvider 缓存的是旧值）
    final prefs = await SharedPreferences.getInstance();
    final currentStoreId = prefs.getString('store_id') ?? 'main';

    Future<void> trySignIn(String pwd) async {
      final res = await supabase.auth.signInWithPassword(email: email, password: pwd);
      if (res.session != null) {
        debugPrint('[SupabaseAuth] 登录成功: ${email.split('@').first}');
      }
    }

    // 1) 先尝试原始密码登录
    try {
      await trySignIn(password);
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuth] 原始密码登录失败: ${e.message}');
    }

    // 2) 原始密码失败且与补齐密码不同，尝试补齐密码登录（兼容 4 位 PIN）
    if (supabase.auth.currentSession == null && effectivePassword != password) {
      try {
        await trySignIn(effectivePassword);
      } on AuthException catch (e) {
        debugPrint('[SupabaseAuth] 补齐密码登录失败: ${e.message}');
      }
    }

    // 3) 仍没有 session → 自动注册
    if (supabase.auth.currentSession == null) {
      try {
        final res = await supabase.auth.signUp(
          email: email,
          password: effectivePassword,
          data: {
            'display_name': user.displayName,
            'username': user.username,
            'role': user.role.name,
            'phone': user.phone,
            'store_id': currentStoreId,
          },
        );
        if (res.session != null) {
          debugPrint('[SupabaseAuth] 注册并自动登录成功: $email');
        } else {
          // auto-confirm 触发器理论上会返回 session；如果没返回，再显式登录一次
          await supabase.auth.signInWithPassword(email: email, password: effectivePassword);
          debugPrint('[SupabaseAuth] 注册后二次登录成功: $email');
        }
      } on AuthException catch (e) {
        debugPrint('[SupabaseAuth] 注册失败: ${e.message}');
        // 用户已存在但登录失败时，再试一次补齐密码登录
        if (e.message.toLowerCase().contains('already') ||
            e.message.toLowerCase().contains('registered') ||
            e.statusCode?.toString() == '422') {
          try {
            await trySignIn(effectivePassword);
          } on AuthException catch (e2) {
            debugPrint('[SupabaseAuth] 用户已存在但登录仍失败: ${e2.message}');
          }
        }
      }
    }

    // 4) 登录成功后同步 store_id 到 profiles 表
    if (supabase.auth.currentSession != null) {
      try {
        await supabase.from('profiles').update({
          'store_id': currentStoreId,
          'username': user.username,
          'phone': user.phone,
          'role': user.role.name,
          'display_name': user.displayName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', supabase.auth.currentUser!.id);
        debugPrint('[SupabaseAuth] profile store_id 已同步: $currentStoreId');
      } catch (e) {
        debugPrint('[SupabaseAuth] 同步 profile store_id 失败: $e');
      }
      // ★ v6.32: 额外保存 refreshToken，覆盖安装后能自动恢复 session
      try {
        final rt = supabase.auth.currentSession!.refreshToken;
        if (rt != null && rt.isNotEmpty) {
          await prefs.setString('supabase_refresh_token', rt);
          debugPrint('[SupabaseAuth] refreshToken 已保存');
        }
      } catch (_) {}
    } else {
      debugPrint('[SupabaseAuth] 最终仍未获得 session，云端同步将以 anon 身份进行');
    }
  }

  /// ★ v6.31: 获取当前 Supabase JWT token（同步服务用）
  String? get supabaseAccessToken {
    return Supabase.instance.client.auth.currentSession?.accessToken;
  }

  Future<void> logout() async {
    _currentUser = '';
    _currentUserRole = null;
    _isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
    await prefs.remove('current_user_role');
    await prefs.remove('current_user_username');
    await prefs.setBool('is_logged_in', false);
    // ★ v6.31: 登出 Supabase Auth
    await Supabase.instance.client.auth.signOut();
    notifyListeners();
  }

  Future<void> setStoreName(String name) async {
    _storeName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_name', name);
    notifyListeners();
  }

  /// ★ v6.31：从 SharedPreferences 刷新门店名称（同步完成后调用）
  Future<void> loadStoreName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('store_name') ?? '';
    if (name != _storeName) {
      _storeName = name;
      notifyListeners();
    }
  }

  /// ★ v6.3: 设置当前超市ID（切换超市或注册新超市时调用）
  Future<void> setStoreId(String id) async {
    _storeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_id', id);
    // 同步给 SupabaseSyncService
    await SupabaseSyncService().setStoreId(id);
    notifyListeners();
  }

  void setOfflineMode(bool value) {
    _isOfflineMode = value;
    notifyListeners();
  }

  void setPendingSyncCount(int count) {
    _pendingSyncCount = count;
    notifyListeners();
  }

  /// 店长或管理员拥有最高权限
  bool get isManager => _currentUserRole == local_user.UserRole.admin || _currentUserRole == local_user.UserRole.manager;

  String getProductDisplayName(String? nameCn, String? nameRu, String? nameUz) {
    switch (_languageCode) {
      case 'ru':
        return nameRu ?? nameCn ?? '';
      case 'uz':
        return nameUz ?? nameCn ?? '';
      default:
        return nameCn ?? '';
    }
  }
}
