// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Супермаркет Менеджер';

  @override
  String get inventory => 'Инвентарь';

  @override
  String get stockIn => 'Приход';

  @override
  String get stockOut => 'Расход';

  @override
  String get check => 'Инвентаризация';

  @override
  String get report => 'Отчеты';

  @override
  String get more => 'Еще';

  @override
  String get scanBarcode => 'Сканировать штрихкод';

  @override
  String get barcode => 'Штрихкод';

  @override
  String get productName => 'Название товара';

  @override
  String get category => 'Категория';

  @override
  String get quantity => 'Количество';

  @override
  String get price => 'Цена';

  @override
  String get priceCny => 'Цена закупки (CNY)';

  @override
  String get priceUzs => 'Цена продажи (UZS)';

  @override
  String get shelfLocation => 'Место на полке';

  @override
  String get expiryDate => 'Срок годности';

  @override
  String daysUntilExpiry(Object days) {
    return 'Осталось $days дней';
  }

  @override
  String get expired => 'Просрочено';

  @override
  String get nearExpiry => 'Истекает срок';

  @override
  String get lowStock => 'Низкий запас';

  @override
  String get inStock => 'В наличии';

  @override
  String get outOfStock => 'Нет в наличии';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get delete => 'Удалить';

  @override
  String get edit => 'Редактировать';

  @override
  String get search => 'Поиск';

  @override
  String get filter => 'Фильтр';

  @override
  String get all => 'Все';

  @override
  String get today => 'Сегодня';

  @override
  String get thisWeek => 'Эта неделя';

  @override
  String get thisMonth => 'Этот месяц';

  @override
  String get submit => 'Отправить';

  @override
  String get success => 'Успешно';

  @override
  String get error => 'Ошибка';

  @override
  String get loading => 'Загрузка...';

  @override
  String get noData => 'Нет данных';

  @override
  String get offlineMode => 'Офлайн режим';

  @override
  String get onlineMode => 'Онлайн режим';

  @override
  String get syncData => 'Синхронизировать';

  @override
  String get dashboard => 'Панель';

  @override
  String get totalProducts => 'Всего товаров';

  @override
  String get totalInventory => 'Общий запас';

  @override
  String get lowStockAlert => 'Низкий запас';

  @override
  String get todayInbound => 'Приход сегодня';

  @override
  String get todayOutbound => 'Расход сегодня';

  @override
  String get pendingChecks => 'Ожидают инвентаризации';

  @override
  String get expiryAlert => 'Истекает срок';

  @override
  String get expiredProducts => 'Просроченные товары';

  @override
  String get inventoryList => 'Список запасов';

  @override
  String get stockInRecord => 'Приходные записи';

  @override
  String get stockOutRecord => 'Расходные записи';

  @override
  String get checkTask => 'Задача инвентаризации';

  @override
  String get newCheckTask => 'Новая инвентаризация';

  @override
  String get startCheck => 'Начать инвентаризацию';

  @override
  String get scanToCheck => 'Сканировать для учета';

  @override
  String get systemQty => 'Кол-во в системе';

  @override
  String get actualQty => 'Фактическое кол-во';

  @override
  String get difference => 'Разница';

  @override
  String get surplus => 'Излишек';

  @override
  String get shortage => 'Недостача';

  @override
  String get checkReport => 'Отчет об инвентаризации';

  @override
  String get differenceTrend => 'Тренд разниц';

  @override
  String get shelfManagement => 'Управление полками';

  @override
  String get bindProduct => 'Привязать товар';

  @override
  String get findProduct => 'Найти товар';

  @override
  String get userManagement => 'Управление персоналом';

  @override
  String get operationLog => 'Журнал операций';

  @override
  String get role => 'Роль';

  @override
  String get admin => 'Администратор';

  @override
  String get manager => 'Менеджер';

  @override
  String get cashier => 'Кассир';

  @override
  String get stockKeeper => 'Кладовщик';

  @override
  String get settings => 'Настройки';

  @override
  String get language => 'Язык';

  @override
  String get chinese => 'Китайский';

  @override
  String get russian => 'Русский';

  @override
  String get uzbek => 'Узбекский';

  @override
  String get currencyDisplay => 'Отображение валют';

  @override
  String get timezone => 'Часовой пояс';

  @override
  String get utcPlus5 => 'Узбекистан UTC+5';

  @override
  String get barcodeSupport => 'Поддержка штрихкодов';

  @override
  String get ean13 => 'EAN-13 (Китай)';

  @override
  String get localBarcode => 'Местные штрихкоды';

  @override
  String get logout => 'Выйти';

  @override
  String get login => 'Войти';

  @override
  String get username => 'Имя пользователя';

  @override
  String get password => 'Пароль';

  @override
  String get welcome => 'Добро пожаловать';

  @override
  String get selectCategory => 'Выберите категорию';

  @override
  String get selectShelf => 'Выберите полку';

  @override
  String get inboundConfirm => 'Подтвердить приход';

  @override
  String get outboundConfirm => 'Подтвердить расход';

  @override
  String get outboundReason => 'Причина расхода';

  @override
  String get sale => 'Продажа';

  @override
  String get loss => 'Потери';

  @override
  String get damage => 'Повреждение';

  @override
  String get returnToSupplier => 'Возврат поставщику';

  @override
  String get other => 'Другое';

  @override
  String get note => 'Примечание';

  @override
  String get operator => 'Оператор';

  @override
  String get date => 'Дата';

  @override
  String get time => 'Время';

  @override
  String syncPending(Object count) {
    return 'Ожидает синхронизации: $count';
  }

  @override
  String get dataSynced => 'Данные синхронизированы';

  @override
  String get networkUnavailable => 'Нет сети, включен офлайн режим';

  @override
  String get scanTips => 'Наведите камеру на штрихкод';

  @override
  String get batchScanMode => 'Пакетное сканирование';

  @override
  String get singleScanMode => 'Одиночное сканирование';

  @override
  String get inputManually => 'Ввести вручную';

  @override
  String get pleaseInputQty => 'Введите количество';

  @override
  String get qtyMustGreaterThanZero => 'Количество должно быть больше 0';

  @override
  String get productNotFound => 'Товар не найден, добавить?';

  @override
  String get createProduct => 'Новый товар';

  @override
  String get supplier => 'Поставщик';

  @override
  String get unit => 'Ед. изм.';

  @override
  String get shelfLife => 'Срок годности (дней)';

  @override
  String get productionDate => 'Дата производства';

  @override
  String get quickFind => 'Быстрый поиск';

  @override
  String get scanResult => 'Результат сканирования';

  @override
  String get continueScan => 'Продолжить';

  @override
  String get finish => 'Завершить';

  @override
  String get viewDetails => 'Подробнее';

  @override
  String get trendChart => 'График тренда';

  @override
  String get statistics => 'Статистика';

  @override
  String get totalSurplus => 'Общий излишек';

  @override
  String get totalShortage => 'Общая недостача';

  @override
  String get matchRate => 'Совпадение';

  @override
  String get inventoryByCategory => 'По категориям';

  @override
  String get inventoryByShelf => 'По полкам';
}
