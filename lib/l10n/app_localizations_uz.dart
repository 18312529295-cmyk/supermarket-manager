// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'Supermarket Menejeri';

  @override
  String get inventory => 'Inventar';

  @override
  String get stockIn => 'Kirish';

  @override
  String get stockOut => 'Chiqish';

  @override
  String get check => 'Tekshiruv';

  @override
  String get report => 'Hisobotlar';

  @override
  String get more => 'Ko\'proq';

  @override
  String get scanBarcode => 'Shtrix-kodni skanerlash';

  @override
  String get barcode => 'Shtrix-kod';

  @override
  String get productName => 'Mahsulot nomi';

  @override
  String get category => 'Kategoriya';

  @override
  String get quantity => 'Miqdor';

  @override
  String get price => 'Narx';

  @override
  String get priceCny => 'Xitoy yuani (CNY)';

  @override
  String get priceUzs => 'So\'m (UZS)';

  @override
  String get shelfLocation => 'Tokcha joylashuvi';

  @override
  String get expiryDate => 'Yaroqlilik muddati';

  @override
  String daysUntilExpiry(Object days) {
    return '$days kun qoldi';
  }

  @override
  String get expired => 'Muddati o\'tgan';

  @override
  String get nearExpiry => 'Muddati tugayapti';

  @override
  String get lowStock => 'Kam qoldi';

  @override
  String get inStock => 'Bor';

  @override
  String get outOfStock => 'Yo\'q';

  @override
  String get confirm => 'Tasdiqlash';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get save => 'Saqlash';

  @override
  String get delete => 'O\'chirish';

  @override
  String get edit => 'Tahrirlash';

  @override
  String get search => 'Qidirish';

  @override
  String get filter => 'Filtrlash';

  @override
  String get all => 'Hammasi';

  @override
  String get today => 'Bugun';

  @override
  String get thisWeek => 'Shu hafta';

  @override
  String get thisMonth => 'Shu oy';

  @override
  String get submit => 'Yuborish';

  @override
  String get success => 'Muvaffaqiyatli';

  @override
  String get error => 'Xato';

  @override
  String get loading => 'Yuklanmoqda...';

  @override
  String get noData => 'Ma\'lumot yo\'q';

  @override
  String get offlineMode => 'Oflayn rejim';

  @override
  String get onlineMode => 'Onlayn rejim';

  @override
  String get syncData => 'Sinxronlash';

  @override
  String get dashboard => 'Boshqaruv paneli';

  @override
  String get totalProducts => 'Jami mahsulotlar';

  @override
  String get totalInventory => 'Jami inventar';

  @override
  String get lowStockAlert => 'Kam qolganlar';

  @override
  String get todayInbound => 'Bugun kirim';

  @override
  String get todayOutbound => 'Bugun chiqim';

  @override
  String get pendingChecks => 'Kutayotgan tekshiruvlar';

  @override
  String get expiryAlert => 'Muddati tugayotganlar';

  @override
  String get expiredProducts => 'Muddati o\'tganlar';

  @override
  String get inventoryList => 'Inventar ro\'yxati';

  @override
  String get stockInRecord => 'Kirim yozuvlari';

  @override
  String get stockOutRecord => 'Chiqim yozuvlari';

  @override
  String get checkTask => 'Tekshiruv vazifasi';

  @override
  String get newCheckTask => 'Yangi tekshiruv';

  @override
  String get startCheck => 'Tekshiruvni boshlash';

  @override
  String get scanToCheck => 'Tekshirish uchun skanerlash';

  @override
  String get systemQty => 'Tizimdagi miqdor';

  @override
  String get actualQty => 'Haqiqiy miqdor';

  @override
  String get difference => 'Farq';

  @override
  String get surplus => 'Ortiqcha';

  @override
  String get shortage => 'Kamchilik';

  @override
  String get checkReport => 'Tekshiruv hisoboti';

  @override
  String get differenceTrend => 'Farq tendentsiyasi';

  @override
  String get shelfManagement => 'Tokcha boshqaruvi';

  @override
  String get bindProduct => 'Mahsulotni bog\'lash';

  @override
  String get findProduct => 'Mahsulotni topish';

  @override
  String get userManagement => 'Xodimlar boshqaruvi';

  @override
  String get operationLog => 'Amaliyot jurnali';

  @override
  String get role => 'Rol';

  @override
  String get admin => 'Administrator';

  @override
  String get manager => 'Menejer';

  @override
  String get cashier => 'Kassir';

  @override
  String get stockKeeper => 'Omborchi';

  @override
  String get settings => 'Sozlamalar';

  @override
  String get language => 'Til';

  @override
  String get chinese => 'Xitoycha';

  @override
  String get russian => 'Ruscha';

  @override
  String get uzbek => 'O\'zbekcha';

  @override
  String get currencyDisplay => 'Valyuta ko\'rinishi';

  @override
  String get timezone => 'Vaqt zonasi';

  @override
  String get utcPlus5 => 'O\'zbekiston UTC+5';

  @override
  String get barcodeSupport => 'Shtrix-kod qo\'llab-quvvatlash';

  @override
  String get ean13 => 'EAN-13 (Xitoy)';

  @override
  String get localBarcode => 'Mahalliy shtrix-kodlar';

  @override
  String get logout => 'Chiqish';

  @override
  String get login => 'Kirish';

  @override
  String get username => 'Foydalanuvchi nomi';

  @override
  String get password => 'Parol';

  @override
  String get welcome => 'Supermarket menejeriga xush kelibsiz';

  @override
  String get selectCategory => 'Kategoriyani tanlang';

  @override
  String get selectShelf => 'Tokchani tanlang';

  @override
  String get inboundConfirm => 'Kirimni tasdiqlash';

  @override
  String get outboundConfirm => 'Chiqimni tasdiqlash';

  @override
  String get outboundReason => 'Chiqim sababi';

  @override
  String get sale => 'Sotuv';

  @override
  String get loss => 'Yoqotish';

  @override
  String get damage => 'Shikastlanish';

  @override
  String get returnToSupplier => 'Yetkazib beruvchiga qaytarish';

  @override
  String get other => 'Boshqa';

  @override
  String get note => 'Izoh';

  @override
  String get operator => 'Operator';

  @override
  String get date => 'Sana';

  @override
  String get time => 'Vaqt';

  @override
  String syncPending(Object count) {
    return 'Sinxronlash kutilmoqda: $count';
  }

  @override
  String get dataSynced => 'Ma\'lumotlar sinxronlandi';

  @override
  String get networkUnavailable => 'Internet yo\'q, oflayn rejimga o\'tildi';

  @override
  String get scanTips => 'Shtrix-kodni kameraga yo\'naltiring';

  @override
  String get batchScanMode => 'Batch skanerlash';

  @override
  String get singleScanMode => 'Yagona skanerlash';

  @override
  String get inputManually => 'Qo\'lda kiritish';

  @override
  String get pleaseInputQty => 'Miqdorni kiriting';

  @override
  String get qtyMustGreaterThanZero => 'Miqdor 0 dan katta bo\'lishi kerak';

  @override
  String get productNotFound => 'Mahsulot topilmadi, qo\'shilsinmi?';

  @override
  String get createProduct => 'Yangi mahsulot';

  @override
  String get supplier => 'Yetkazib beruvchi';

  @override
  String get unit => 'Birlik';

  @override
  String get shelfLife => 'Yaroqlilik muddati (kun)';

  @override
  String get productionDate => 'Ishlab chiqarilgan sana';

  @override
  String get quickFind => 'Tezkor qidirish';

  @override
  String get scanResult => 'Skanerlash natijasi';

  @override
  String get continueScan => 'Davom etish';

  @override
  String get finish => 'Yakunlash';

  @override
  String get viewDetails => 'Batafsil';

  @override
  String get trendChart => 'Trend grafigi';

  @override
  String get statistics => 'Statistika';

  @override
  String get totalSurplus => 'Jami ortiqcha';

  @override
  String get totalShortage => 'Jami kamchilik';

  @override
  String get matchRate => 'Moslashuv darajasi';

  @override
  String get inventoryByCategory => 'Kategoriya bo\'yicha';

  @override
  String get inventoryByShelf => 'Tokcha bo\'yicha';
}
