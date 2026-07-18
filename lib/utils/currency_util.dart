import 'package:intl/intl.dart';

class CurrencyUtil {
  static final NumberFormat _cnyFormat = NumberFormat.currency(
    locale: 'zh_CN',
    symbol: '¥',
    decimalDigits: 2,
  );

  static final NumberFormat _uzsFormat = NumberFormat.currency(
    locale: 'uz_UZ',
    symbol: '',
    decimalDigits: 0,
  );

  static String formatCny(double amount) {
    return _cnyFormat.format(amount);
  }

  /// ★ v6.31: 动态货币符号 — 从 AppProvider.countryConfig.currencySymbol 传入
  /// 避免硬编码 "so'm"，支持多国家货币的符号动态切换
  static String formatUzs(double amount, {String symbol = "so'm"}) {
    final formatted = _uzsFormat.format(amount);
    return '$formatted $symbol';
  }

  static String format(double amount, String currency, {String uzsSymbol = "so'm"}) {
    if (currency == 'UZS') {
      return formatUzs(amount, symbol: uzsSymbol);
    }
    return formatCny(amount);
  }

  static String formatCompact(double amount, String currency, {String uzsSymbol = "so'm"}) {
    if (currency == 'UZS') {
      return '${amount.toStringAsFixed(0)} $uzsSymbol';
    }
    return '¥${amount.toStringAsFixed(2)}';
  }
}
