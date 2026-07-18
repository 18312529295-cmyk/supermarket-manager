import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_provider.dart';
import 'providers/inventory_provider.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'config/supabase_config.dart';
import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'utils/date_util.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DateUtil.initialize();

  // ★ v6.31: 初始化 Supabase Auth
  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // 检查是否已初始化
  final prefs = await SharedPreferences.getInstance();
  final isInitialized = prefs.getBool('app_initialized') ?? false;
  final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

  runApp(SupermarketApp(
    isInitialized: isInitialized,
    isLoggedIn: isLoggedIn,
  ));
}

class SupermarketApp extends StatefulWidget {
  final bool isInitialized;
  final bool isLoggedIn;

  const SupermarketApp({
    super.key,
    required this.isInitialized,
    required this.isLoggedIn,
  });

  @override
  State<SupermarketApp> createState() => _SupermarketAppState();
}

class _SupermarketAppState extends State<SupermarketApp> {
  late bool _isInitialized;
  late bool _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _isInitialized = widget.isInitialized;
    _isLoggedIn = widget.isLoggedIn;
  }

  /// 刷新初始化状态（LoginScreen 调用跳过初始化后）
  void refreshInitState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isInitialized = prefs.getBool('app_initialized') ?? false;
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
      ],
      child: Consumer<AppProvider>(
        builder: (context, appProvider, child) {
          Widget home;
          if (!_isInitialized) {
            home = InitWizardScreen(onInitComplete: refreshInitState);
          } else if (!appProvider.isLoggedIn && !_isLoggedIn) {
            home = LoginScreen(onSkipInit: refreshInitState);
          } else {
            home = const HomeScreen();
          }

          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: Locale(appProvider.languageCode),
            supportedLocales: const [
              Locale('zh'),
              Locale('ru'),
              Locale('uz'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: home,
          );
        },
      ),
    );
  }
}
