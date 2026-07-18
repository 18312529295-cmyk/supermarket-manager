import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = '华人超市管家';
  static const String appVersion = '6.30.0';

  // Timezone
  static const String defaultTimezone = 'Asia/Tashkent'; // UTC+5
  static const int utcOffsetHours = 5;

  // Currency
  static const String currencyCNY = 'CNY'; // 人民币
  static const String currencyUZS = 'UZS'; // 乌兹别克索姆
  static const String symbolCNY = '¥';
  /// ★ v6.31: 货币符号统一使用 ASCII 撇号，与 CountryConfig 保持一致
  /// 动态货币符号应从 AppProvider.countryConfig.currencySymbol 获取
  static const String symbolUZS = "so'm";

  // Barcode
  static const List<String> supportedBarcodeFormats = [
    'EAN_13',
    'EAN_8',
    'UPC_A',
    'UPC_E',
    'CODE_128',
    'CODE_39',
    'ITF',
    'CODABAR',
  ];

  // Low Stock Threshold
  static const int lowStockThreshold = 10;

  // Expiry Warning Days
  static const int expiryWarningDays = 7;

  // Colors
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color secondaryColor = Color(0xFFFF6F00);
  static const Color dangerColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF388E3C);
  static const Color warningColor = Color(0xFFFBC02D);
  static const Color lowStockColor = Color(0xFFE53935);

  // Sync
  static const Duration syncInterval = Duration(minutes: 5);

  // Database
  static const String dbName = 'supermarket.db';
  static const int dbVersion = 14;
}
