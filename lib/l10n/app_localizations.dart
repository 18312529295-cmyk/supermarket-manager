import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ms.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uz.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ms'),
    Locale('ru'),
    Locale('tr'),
    Locale('uz'),
    Locale('vi'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'华人超市管家'**
  String get appTitle;

  /// No description provided for @inventory.
  ///
  /// In zh, this message translates to:
  /// **'库存'**
  String get inventory;

  /// No description provided for @stockIn.
  ///
  /// In zh, this message translates to:
  /// **'入库'**
  String get stockIn;

  /// No description provided for @stockOut.
  ///
  /// In zh, this message translates to:
  /// **'出库'**
  String get stockOut;

  /// No description provided for @check.
  ///
  /// In zh, this message translates to:
  /// **'盘点'**
  String get check;

  /// No description provided for @report.
  ///
  /// In zh, this message translates to:
  /// **'报表'**
  String get report;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @scanBarcode.
  ///
  /// In zh, this message translates to:
  /// **'扫描条码'**
  String get scanBarcode;

  /// No description provided for @barcode.
  ///
  /// In zh, this message translates to:
  /// **'条码'**
  String get barcode;

  /// No description provided for @productName.
  ///
  /// In zh, this message translates to:
  /// **'商品名称'**
  String get productName;

  /// No description provided for @category.
  ///
  /// In zh, this message translates to:
  /// **'品类'**
  String get category;

  /// No description provided for @quantity.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In zh, this message translates to:
  /// **'价格'**
  String get price;

  /// No description provided for @priceCny.
  ///
  /// In zh, this message translates to:
  /// **'人民币进价'**
  String get priceCny;

  /// No description provided for @priceUzs.
  ///
  /// In zh, this message translates to:
  /// **'索姆售价'**
  String get priceUzs;

  /// No description provided for @shelfLocation.
  ///
  /// In zh, this message translates to:
  /// **'货架位置'**
  String get shelfLocation;

  /// No description provided for @expiryDate.
  ///
  /// In zh, this message translates to:
  /// **'保质期至'**
  String get expiryDate;

  /// No description provided for @daysUntilExpiry.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {days} 天'**
  String daysUntilExpiry(Object days);

  /// No description provided for @expired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get expired;

  /// No description provided for @nearExpiry.
  ///
  /// In zh, this message translates to:
  /// **'临期'**
  String get nearExpiry;

  /// No description provided for @lowStock.
  ///
  /// In zh, this message translates to:
  /// **'低库存'**
  String get lowStock;

  /// No description provided for @inStock.
  ///
  /// In zh, this message translates to:
  /// **'有货'**
  String get inStock;

  /// No description provided for @outOfStock.
  ///
  /// In zh, this message translates to:
  /// **'缺货'**
  String get outOfStock;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get filter;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get thisMonth;

  /// No description provided for @submit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get submit;

  /// No description provided for @success.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get success;

  /// No description provided for @error.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get error;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get loading;

  /// No description provided for @noData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get noData;

  /// No description provided for @offlineMode.
  ///
  /// In zh, this message translates to:
  /// **'离线模式'**
  String get offlineMode;

  /// No description provided for @onlineMode.
  ///
  /// In zh, this message translates to:
  /// **'在线模式'**
  String get onlineMode;

  /// No description provided for @syncData.
  ///
  /// In zh, this message translates to:
  /// **'同步数据'**
  String get syncData;

  /// No description provided for @dashboard.
  ///
  /// In zh, this message translates to:
  /// **'看板'**
  String get dashboard;

  /// No description provided for @totalProducts.
  ///
  /// In zh, this message translates to:
  /// **'商品总数'**
  String get totalProducts;

  /// No description provided for @totalInventory.
  ///
  /// In zh, this message translates to:
  /// **'库存总量'**
  String get totalInventory;

  /// No description provided for @lowStockAlert.
  ///
  /// In zh, this message translates to:
  /// **'低库存预警'**
  String get lowStockAlert;

  /// No description provided for @todayInbound.
  ///
  /// In zh, this message translates to:
  /// **'今日入库'**
  String get todayInbound;

  /// No description provided for @todayOutbound.
  ///
  /// In zh, this message translates to:
  /// **'今日出库'**
  String get todayOutbound;

  /// No description provided for @pendingChecks.
  ///
  /// In zh, this message translates to:
  /// **'待盘点任务'**
  String get pendingChecks;

  /// No description provided for @expiryAlert.
  ///
  /// In zh, this message translates to:
  /// **'临期提醒'**
  String get expiryAlert;

  /// No description provided for @expiredProducts.
  ///
  /// In zh, this message translates to:
  /// **'已过期商品'**
  String get expiredProducts;

  /// No description provided for @inventoryList.
  ///
  /// In zh, this message translates to:
  /// **'库存列表'**
  String get inventoryList;

  /// No description provided for @stockInRecord.
  ///
  /// In zh, this message translates to:
  /// **'入库记录'**
  String get stockInRecord;

  /// No description provided for @stockOutRecord.
  ///
  /// In zh, this message translates to:
  /// **'出库记录'**
  String get stockOutRecord;

  /// No description provided for @checkTask.
  ///
  /// In zh, this message translates to:
  /// **'盘点任务'**
  String get checkTask;

  /// No description provided for @newCheckTask.
  ///
  /// In zh, this message translates to:
  /// **'新建盘点'**
  String get newCheckTask;

  /// No description provided for @startCheck.
  ///
  /// In zh, this message translates to:
  /// **'开始盘点'**
  String get startCheck;

  /// No description provided for @scanToCheck.
  ///
  /// In zh, this message translates to:
  /// **'扫码盘点'**
  String get scanToCheck;

  /// No description provided for @systemQty.
  ///
  /// In zh, this message translates to:
  /// **'系统数量'**
  String get systemQty;

  /// No description provided for @actualQty.
  ///
  /// In zh, this message translates to:
  /// **'实际数量'**
  String get actualQty;

  /// No description provided for @difference.
  ///
  /// In zh, this message translates to:
  /// **'差异'**
  String get difference;

  /// No description provided for @surplus.
  ///
  /// In zh, this message translates to:
  /// **'盘盈'**
  String get surplus;

  /// No description provided for @shortage.
  ///
  /// In zh, this message translates to:
  /// **'盘亏'**
  String get shortage;

  /// No description provided for @checkReport.
  ///
  /// In zh, this message translates to:
  /// **'盘点报告'**
  String get checkReport;

  /// No description provided for @differenceTrend.
  ///
  /// In zh, this message translates to:
  /// **'差异趋势'**
  String get differenceTrend;

  /// No description provided for @shelfManagement.
  ///
  /// In zh, this message translates to:
  /// **'货架管理'**
  String get shelfManagement;

  /// No description provided for @bindProduct.
  ///
  /// In zh, this message translates to:
  /// **'绑定商品'**
  String get bindProduct;

  /// No description provided for @findProduct.
  ///
  /// In zh, this message translates to:
  /// **'查找商品'**
  String get findProduct;

  /// No description provided for @userManagement.
  ///
  /// In zh, this message translates to:
  /// **'人员管理'**
  String get userManagement;

  /// No description provided for @operationLog.
  ///
  /// In zh, this message translates to:
  /// **'操作记录'**
  String get operationLog;

  /// No description provided for @role.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get role;

  /// No description provided for @admin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get admin;

  /// No description provided for @manager.
  ///
  /// In zh, this message translates to:
  /// **'店长'**
  String get manager;

  /// No description provided for @cashier.
  ///
  /// In zh, this message translates to:
  /// **'收银员'**
  String get cashier;

  /// No description provided for @stockKeeper.
  ///
  /// In zh, this message translates to:
  /// **'仓管员'**
  String get stockKeeper;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @chinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @russian.
  ///
  /// In zh, this message translates to:
  /// **'俄语'**
  String get russian;

  /// No description provided for @uzbek.
  ///
  /// In zh, this message translates to:
  /// **'乌兹别克语'**
  String get uzbek;

  /// No description provided for @currencyDisplay.
  ///
  /// In zh, this message translates to:
  /// **'货币显示'**
  String get currencyDisplay;

  /// No description provided for @timezone.
  ///
  /// In zh, this message translates to:
  /// **'时区'**
  String get timezone;

  /// No description provided for @utcPlus5.
  ///
  /// In zh, this message translates to:
  /// **'乌兹别克斯坦 UTC+5'**
  String get utcPlus5;

  /// No description provided for @barcodeSupport.
  ///
  /// In zh, this message translates to:
  /// **'条码兼容'**
  String get barcodeSupport;

  /// No description provided for @ean13.
  ///
  /// In zh, this message translates to:
  /// **'EAN-13 (中国商品)'**
  String get ean13;

  /// No description provided for @localBarcode.
  ///
  /// In zh, this message translates to:
  /// **'本地条码'**
  String get localBarcode;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @welcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用华人超市管家'**
  String get welcome;

  /// No description provided for @selectCategory.
  ///
  /// In zh, this message translates to:
  /// **'选择品类'**
  String get selectCategory;

  /// No description provided for @selectShelf.
  ///
  /// In zh, this message translates to:
  /// **'选择货架'**
  String get selectShelf;

  /// No description provided for @inboundConfirm.
  ///
  /// In zh, this message translates to:
  /// **'入库确认'**
  String get inboundConfirm;

  /// No description provided for @outboundConfirm.
  ///
  /// In zh, this message translates to:
  /// **'出库确认'**
  String get outboundConfirm;

  /// No description provided for @outboundReason.
  ///
  /// In zh, this message translates to:
  /// **'出库原因'**
  String get outboundReason;

  /// No description provided for @sale.
  ///
  /// In zh, this message translates to:
  /// **'销售'**
  String get sale;

  /// No description provided for @loss.
  ///
  /// In zh, this message translates to:
  /// **'损耗'**
  String get loss;

  /// No description provided for @damage.
  ///
  /// In zh, this message translates to:
  /// **'破损'**
  String get damage;

  /// No description provided for @returnToSupplier.
  ///
  /// In zh, this message translates to:
  /// **'退货'**
  String get returnToSupplier;

  /// No description provided for @other.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get other;

  /// No description provided for @note.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get note;

  /// No description provided for @operator.
  ///
  /// In zh, this message translates to:
  /// **'操作人'**
  String get operator;

  /// No description provided for @date.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get date;

  /// No description provided for @time.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get time;

  /// No description provided for @syncPending.
  ///
  /// In zh, this message translates to:
  /// **'待同步 {count} 条'**
  String syncPending(Object count);

  /// No description provided for @dataSynced.
  ///
  /// In zh, this message translates to:
  /// **'数据已同步'**
  String get dataSynced;

  /// No description provided for @networkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，已切换至离线模式'**
  String get networkUnavailable;

  /// No description provided for @scanTips.
  ///
  /// In zh, this message translates to:
  /// **'将条码对准扫描框'**
  String get scanTips;

  /// No description provided for @batchScanMode.
  ///
  /// In zh, this message translates to:
  /// **'批量扫描模式'**
  String get batchScanMode;

  /// No description provided for @singleScanMode.
  ///
  /// In zh, this message translates to:
  /// **'单次扫描模式'**
  String get singleScanMode;

  /// No description provided for @inputManually.
  ///
  /// In zh, this message translates to:
  /// **'手动输入'**
  String get inputManually;

  /// No description provided for @pleaseInputQty.
  ///
  /// In zh, this message translates to:
  /// **'请输入数量'**
  String get pleaseInputQty;

  /// No description provided for @qtyMustGreaterThanZero.
  ///
  /// In zh, this message translates to:
  /// **'数量必须大于0'**
  String get qtyMustGreaterThanZero;

  /// No description provided for @productNotFound.
  ///
  /// In zh, this message translates to:
  /// **'商品不存在，是否新增？'**
  String get productNotFound;

  /// No description provided for @createProduct.
  ///
  /// In zh, this message translates to:
  /// **'新增商品'**
  String get createProduct;

  /// No description provided for @supplier.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get supplier;

  /// No description provided for @unit.
  ///
  /// In zh, this message translates to:
  /// **'单位'**
  String get unit;

  /// No description provided for @shelfLife.
  ///
  /// In zh, this message translates to:
  /// **'保质期(天)'**
  String get shelfLife;

  /// No description provided for @productionDate.
  ///
  /// In zh, this message translates to:
  /// **'生产日期'**
  String get productionDate;

  /// No description provided for @quickFind.
  ///
  /// In zh, this message translates to:
  /// **'快速找货'**
  String get quickFind;

  /// No description provided for @scanResult.
  ///
  /// In zh, this message translates to:
  /// **'扫描结果'**
  String get scanResult;

  /// No description provided for @continueScan.
  ///
  /// In zh, this message translates to:
  /// **'继续扫描'**
  String get continueScan;

  /// No description provided for @finish.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get finish;

  /// No description provided for @viewDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get viewDetails;

  /// No description provided for @trendChart.
  ///
  /// In zh, this message translates to:
  /// **'趋势图'**
  String get trendChart;

  /// No description provided for @statistics.
  ///
  /// In zh, this message translates to:
  /// **'统计'**
  String get statistics;

  /// No description provided for @totalSurplus.
  ///
  /// In zh, this message translates to:
  /// **'总盘盈'**
  String get totalSurplus;

  /// No description provided for @totalShortage.
  ///
  /// In zh, this message translates to:
  /// **'总盘亏'**
  String get totalShortage;

  /// No description provided for @matchRate.
  ///
  /// In zh, this message translates to:
  /// **'吻合率'**
  String get matchRate;

  /// No description provided for @inventoryByCategory.
  ///
  /// In zh, this message translates to:
  /// **'按品类库存'**
  String get inventoryByCategory;

  /// No description provided for @inventoryByShelf.
  ///
  /// In zh, this message translates to:
  /// **'按货架库存'**
  String get inventoryByShelf;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ms',
        'ru',
        'tr',
        'uz',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ms':
      return AppLocalizationsMs();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'uz':
      return AppLocalizationsUz();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
