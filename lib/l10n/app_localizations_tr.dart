// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'Süpermarket Yöneticisi';

  @override
  String get inventory => 'Envanter';

  @override
  String get stockIn => 'Giriş';

  @override
  String get stockOut => 'Çıkış';

  @override
  String get check => 'Kontrol';

  @override
  String get report => 'Raporlar';

  @override
  String get more => 'Daha Fazla';

  @override
  String get scanBarcode => 'Barkod Tara';

  @override
  String get barcode => 'Barkod';

  @override
  String get productName => 'Ürün Adı';

  @override
  String get category => 'Kategori';

  @override
  String get quantity => 'Miktar';

  @override
  String get price => 'Fiyat';

  @override
  String get priceCny => '人民币进价';

  @override
  String get priceUzs => '索姆售价';

  @override
  String get shelfLocation => '货架位置';

  @override
  String get expiryDate => '保质期至';

  @override
  String daysUntilExpiry(Object days) {
    return '还剩 $days 天';
  }

  @override
  String get expired => '已过期';

  @override
  String get nearExpiry => '临期';

  @override
  String get lowStock => '低库存';

  @override
  String get inStock => '有货';

  @override
  String get outOfStock => '缺货';

  @override
  String get confirm => '确认';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get search => '搜索';

  @override
  String get filter => '筛选';

  @override
  String get all => '全部';

  @override
  String get today => '今日';

  @override
  String get thisWeek => '本周';

  @override
  String get thisMonth => '本月';

  @override
  String get submit => '提交';

  @override
  String get success => '成功';

  @override
  String get error => '错误';

  @override
  String get loading => '加载中...';

  @override
  String get noData => '暂无数据';

  @override
  String get offlineMode => '离线模式';

  @override
  String get onlineMode => '在线模式';

  @override
  String get syncData => '同步数据';

  @override
  String get dashboard => '看板';

  @override
  String get totalProducts => '商品总数';

  @override
  String get totalInventory => '库存总量';

  @override
  String get lowStockAlert => '低库存预警';

  @override
  String get todayInbound => '今日入库';

  @override
  String get todayOutbound => '今日出库';

  @override
  String get pendingChecks => '待盘点任务';

  @override
  String get expiryAlert => '临期提醒';

  @override
  String get expiredProducts => '已过期商品';

  @override
  String get inventoryList => '库存列表';

  @override
  String get stockInRecord => '入库记录';

  @override
  String get stockOutRecord => '出库记录';

  @override
  String get checkTask => '盘点任务';

  @override
  String get newCheckTask => '新建盘点';

  @override
  String get startCheck => '开始盘点';

  @override
  String get scanToCheck => '扫码盘点';

  @override
  String get systemQty => '系统数量';

  @override
  String get actualQty => '实际数量';

  @override
  String get difference => '差异';

  @override
  String get surplus => '盘盈';

  @override
  String get shortage => '盘亏';

  @override
  String get checkReport => '盘点报告';

  @override
  String get differenceTrend => '差异趋势';

  @override
  String get shelfManagement => '货架管理';

  @override
  String get bindProduct => '绑定商品';

  @override
  String get findProduct => '查找商品';

  @override
  String get userManagement => 'Personel Yönetimi';

  @override
  String get operationLog => '操作记录';

  @override
  String get role => '角色';

  @override
  String get admin => '管理员';

  @override
  String get manager => '店长';

  @override
  String get cashier => '收银员';

  @override
  String get stockKeeper => '仓管员';

  @override
  String get settings => 'Ayarlar';

  @override
  String get language => 'Dil';

  @override
  String get chinese => '中文';

  @override
  String get russian => '俄语';

  @override
  String get uzbek => '乌兹别克语';

  @override
  String get currencyDisplay => '货币显示';

  @override
  String get timezone => '时区';

  @override
  String get utcPlus5 => '乌兹别克斯坦 UTC+5';

  @override
  String get barcodeSupport => '条码兼容';

  @override
  String get ean13 => 'EAN-13 (中国商品)';

  @override
  String get localBarcode => '本地条码';

  @override
  String get logout => 'Çıkış Yap';

  @override
  String get login => 'Giriş Yap';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get welcome => '欢迎使用华人超市管家';

  @override
  String get selectCategory => '选择品类';

  @override
  String get selectShelf => '选择货架';

  @override
  String get inboundConfirm => '入库确认';

  @override
  String get outboundConfirm => '出库确认';

  @override
  String get outboundReason => '出库原因';

  @override
  String get sale => '销售';

  @override
  String get loss => '损耗';

  @override
  String get damage => '破损';

  @override
  String get returnToSupplier => '退货';

  @override
  String get other => '其他';

  @override
  String get note => '备注';

  @override
  String get operator => '操作人';

  @override
  String get date => '日期';

  @override
  String get time => '时间';

  @override
  String syncPending(Object count) {
    return '待同步 $count 条';
  }

  @override
  String get dataSynced => '数据已同步';

  @override
  String get networkUnavailable => '网络不可用，已切换至离线模式';

  @override
  String get scanTips => '将条码对准扫描框';

  @override
  String get batchScanMode => '批量扫描模式';

  @override
  String get singleScanMode => '单次扫描模式';

  @override
  String get inputManually => '手动输入';

  @override
  String get pleaseInputQty => '请输入数量';

  @override
  String get qtyMustGreaterThanZero => '数量必须大于0';

  @override
  String get productNotFound => '商品不存在，是否新增？';

  @override
  String get createProduct => '新增商品';

  @override
  String get supplier => '供应商';

  @override
  String get unit => '单位';

  @override
  String get shelfLife => '保质期(天)';

  @override
  String get productionDate => '生产日期';

  @override
  String get quickFind => '快速找货';

  @override
  String get scanResult => '扫描结果';

  @override
  String get continueScan => '继续扫描';

  @override
  String get finish => '完成';

  @override
  String get viewDetails => '查看详情';

  @override
  String get trendChart => '趋势图';

  @override
  String get statistics => '统计';

  @override
  String get totalSurplus => '总盘盈';

  @override
  String get totalShortage => '总盘亏';

  @override
  String get matchRate => '吻合率';

  @override
  String get inventoryByCategory => '按品类库存';

  @override
  String get inventoryByShelf => '按货架库存';
}
