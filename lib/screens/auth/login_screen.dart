import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_provider.dart';
import '../../models/user.dart';
import '../../services/database_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/sync_service.dart';
import '../../utils/password_util.dart';
import '../home_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onSkipInit;

  const LoginScreen({super.key, this.onSkipInit});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 用户名密码登录
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // 手机号验证码登录
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  /// ★ 登录成功后跳转到主界面
  Future<void> _navigateToHome() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  /// 非管理员登录：跳过初始化，直接进入系统
  Future<void> _skipInitAndLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_initialized', true);
    if (!mounted) return;
    widget.onSkipInit?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已跳过初始化，请使用员工账号登录'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 用户名+密码登录
  Future<void> _loginByUsername() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      _showError('请输入用户名和密码');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = await DatabaseService.instance.loginUser(username, password);
      if (user != null && mounted) {
        await context.read<AppProvider>().login(user, password: password);
        await _navigateToHome();
      } else if (mounted) {
        _showError('用户名或密码错误');
      }
    } catch (e) {
      if (mounted) _showError('登录失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 手机号+PIN码登录（支持云端用户同步，自动加入门店）
  Future<void> _loginByPhone() async {
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();
    if (phone.isEmpty || pin.isEmpty) {
      _showError('请输入手机号和PIN码');
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 1) 先查本地
      User? user = await DatabaseService.instance.loginUserByPhone(phone, pin);

      // 2) 本地没找到 → 去云端所有门店查找该手机号
      String? joinedStoreId;
      if (user == null) {
        final cloudResult = await SupabaseSyncService().findUserByPhoneOnCloudAnyStore(phone);
        if (cloudResult != null) {
          final cloudUser = cloudResult['user'] as User;
          joinedStoreId = cloudResult['store_id'] as String?;

          // 云端哈希验证
          if (cloudUser.passwordHash != null &&
              cloudUser.passwordSalt != null &&
              PasswordUtil.verify(pin, cloudUser.passwordSalt!, cloudUser.passwordHash!)) {
            // 自动加入该门店
            if (joinedStoreId != null && joinedStoreId.isNotEmpty) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('store_id', joinedStoreId);
              await prefs.setBool('app_initialized', true);
              await context.read<AppProvider>().setStoreId(joinedStoreId);

              // ★ v6.31 fix: 同时从云端下载门店名称，写入 prefs + AppProvider
              try {
                final sync = SupabaseSyncService();
                await sync.setStoreId(joinedStoreId);
                final storeName = await sync.getStoreNameById(joinedStoreId);
                if (storeName != null && storeName.isNotEmpty) {
                  await prefs.setString('store_name', storeName);
                  await context.read<AppProvider>().setStoreName(storeName);
                }
              } catch (_) {}
            }
            // 云端匹配成功 → 写入本地
            final id = await DatabaseService.instance.insertUser(cloudUser);
            if (id > 0) {
              user = cloudUser.copyWith(id: id);
            }
          }
        }
      }

      if (user != null && mounted) {
        await context.read<AppProvider>().login(user, password: pin);
        await _navigateToHome();
      } else if (mounted) {
        _showError('手机号或PIN码错误\n提示：PIN码为管理员在"人员管理"中设置的数字密码');
      }
    } catch (e) {
      if (mounted) _showError('登录失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade800, Colors.blue.shade400],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store, size: 64, color: Colors.blue),
                      const SizedBox(height: 12),
                      const Text('华人超市管家', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('手机号 + PIN 直接登录', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 16),
                      // 登录方式切换Tab
                      TabBar(
                        controller: _tabController,
                        labelColor: Colors.blue,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.blue,
                        tabs: const [
                          Tab(text: '账号密码', icon: Icon(Icons.person)),
                          Tab(text: '手机号', icon: Icon(Icons.phone)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Tab内容
                      SizedBox(
                        height: 220,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildUsernameLoginForm(),
                            _buildPhoneLoginForm(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_tabController.index == 0) {
                                    _loginByUsername();
                                  } else {
                                    _loginByPhone();
                                  }
                                },
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('登录', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: TextButton.icon(
                          onPressed: _isLoading ? null : _skipInitAndLogin,
                          icon: const Icon(Icons.skip_next, size: 18),
                          label: const Text('跳过初始化，直接登录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ★ 误操作跳过后可以返回初始化界面
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const InitWizardScreen()),
                            (_) => false,
                          );
                        },
                        icon: const Icon(Icons.settings_backup_restore, size: 16),
                        label: const Text('返回初始化设置', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 用户名+密码表单
  Widget _buildUsernameLoginForm() {
    return Column(
      children: [
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: '用户名',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: '密码',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _loginByUsername(),
        ),
      ],
    );
  }

  /// 手机号+PIN码表单
  Widget _buildPhoneLoginForm() {
    return Column(
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            prefixIcon: Icon(Icons.phone),
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN码 (4-6位数字)',
            prefixIcon: Icon(Icons.pin),
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (_) => _loginByPhone(),
        ),
        const SizedBox(height: 8),
        Text(
          'PIN码为管理员在"人员管理"中为每位员工设置的数字密码',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

/// 首次启动初始化向导
class InitWizardScreen extends StatefulWidget {
  final VoidCallback? onInitComplete;

  const InitWizardScreen({super.key, this.onInitComplete});

  @override
  State<InitWizardScreen> createState() => _InitWizardScreenState();
}

class _InitWizardScreenState extends State<InitWizardScreen> {
  final _storeNameController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _managerUserController = TextEditingController();
  final _managerPassController = TextEditingController();
  final _managerPhoneController = TextEditingController();
  String _generatedPin = DatabaseService.generatePin();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _managerPassController.text = _generatedPin;
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _managerNameController.dispose();
    _managerUserController.dispose();
    _managerPassController.dispose();
    _managerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final storeName = _storeNameController.text.trim();
    final managerName = _managerNameController.text.trim();
    final managerUser = _managerUserController.text.trim();
    final managerPass = _managerPassController.text.trim();

    if (storeName.isEmpty || managerName.isEmpty || managerUser.isEmpty || managerPass.isEmpty) {
      _showError('请填写所有必填项');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ★ v6.31: 检查手机号是否已被其他超市使用（手机号与超市强绑定）
      final managerPhone = _managerPhoneController.text.trim();
      if (managerPhone.isNotEmpty) {
        final syncService = SupabaseSyncService();
        final existingStoreId = await syncService.checkPhoneInCloudStores(managerPhone);
        if (existingStoreId != null && existingStoreId.isNotEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showError('该手机号 $managerPhone 已绑定其他超市，请使用其他手机号\n\n提示：一个手机号只能注册一个超市');
          }
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('store_name', storeName);

      // ★ v6.3: 生成唯一 store_id（store_ + 时间戳），存到 prefs
      final storeId = 'store_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('store_id', storeId);
      await prefs.setBool('app_initialized', true);

      // ★ v6.31: 店长即管理员 — 更新默认admin账号为店长信息
      final managerSalt = PasswordUtil.generateSalt();
      final managerHash = PasswordUtil.hashPassword(managerPass, managerSalt);
      final db = await DatabaseService.instance.database;
      // 查找并更新默认admin账号
      final existing = await db.query('users', where: 'username = ?', whereArgs: ['admin'], limit: 1);
      if (existing.isNotEmpty) {
        await db.update('users', {
          'username': managerUser,
          'display_name': managerName,
          'password_hash': managerHash,
          'password_salt': managerSalt,
          'phone': managerPhone.isNotEmpty ? managerPhone : null,
        }, where: 'id = ?', whereArgs: [existing.first['id']]);
      }

      // 登录并跳转
      final user = await DatabaseService.instance.loginUser(managerUser, managerPass);
      if (user != null && mounted) {
        await context.read<AppProvider>().login(user, password: managerPass);
        await context.read<AppProvider>().setStoreName(storeName);
        await context.read<AppProvider>().setStoreId(storeId);  // ★ v6.3
        widget.onInitComplete?.call();

        // ★ 将店长账号同步到云端（另一台手机可以登录）
        final syncService = SyncService();
        if (await syncService.checkConnectivity()) {
          final sync = SupabaseSyncService();
          await sync.setStoreId(storeId);
          // ★ v6.3: 先上传超市信息到 stores 表
          await sync.uploadStoreInfo(
            storeId: storeId,
            name: storeName,
            managerName: managerName,
            phone: managerPhone.isNotEmpty ? managerPhone : null,
          );
          await sync.uploadUser(user);
          // 同时把113个预置商品也上传到云端
          await sync.uploadPresetProducts();
        }

        // ★ v6.31: 不再显示 PIN 码明文，避免公共场所泄露
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('店长账号已创建，请牢记您设置的PIN码\n员工加入时需要输入超市ID'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );
        // ★ 显式导航到主界面
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) _showError('初始化失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade800, Colors.blue.shade400],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Column(
                          children: [
                            Icon(Icons.store, size: 64, color: Colors.blue),
                            SizedBox(height: 16),
                            Text('欢迎使用华人超市管家', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('首次使用，请完成初始化设置', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('① 超市信息', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _storeNameController,
                        decoration: const InputDecoration(
                          labelText: '超市名称 *',
                          hintText: '例如：中亚华联超市',
                          prefixIcon: Icon(Icons.store_mall_directory),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('② 创建店长账号', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _managerNameController,
                        decoration: const InputDecoration(
                          labelText: '店长姓名 *',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _managerUserController,
                        decoration: const InputDecoration(
                          labelText: '登录用户名 *',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ③ PIN码设置
                      const Text('③ 设置登录PIN码', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.pin, color: Colors.orange),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text('PIN码用于手机号登录', style: TextStyle(fontSize: 13)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _generatedPin = DatabaseService.generatePin();
                                      _managerPassController.text = _generatedPin;
                                    });
                                  },
                                  child: const Text('随机生成'),
                                ),
                              ],
                            ),
                            TextField(
                              controller: _managerPassController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: '4-6位数字PIN码',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                              style: const TextStyle(fontSize: 20, letterSpacing: 3, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _managerPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '手机号 (可选，用于手机登录)',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('完成初始化', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (_) => false,
                            );
                          },
                          icon: const Icon(Icons.login, color: Colors.white, size: 18),
                          label: Text(
                            '已有账号？跳过初始化，直接登录',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            backgroundColor: Colors.white24,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
