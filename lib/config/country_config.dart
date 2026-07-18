/// ★ v6.30: 国家/区域配置
/// 用于系统设置中的国家选择，关联语言、货币、时区
class CountryConfig {
  final String code;
  final String nameCn;
  final String nameLocal;
  final String region;       // 东南亚/中亚/欧洲/东亚
  final String langCode;     // Flutter locale code
  final String langName;     // 本地语言显示名
  final String currencyCode;
  final String currencySymbol;
  final String timezone;
  final String timezoneDesc;
  /// ★ v6.31: 人民币对该国货币的近似汇率（1 CNY = ? 当地货币）
  final double cnyExchangeRate;

  const CountryConfig({
    required this.code,
    required this.nameCn,
    required this.nameLocal,
    required this.region,
    required this.langCode,
    required this.langName,
    required this.currencyCode,
    required this.currencySymbol,
    required this.timezone,
    required this.timezoneDesc,
    required this.cnyExchangeRate,
  });

  static const List<CountryConfig> all = [
    // 东亚
    CountryConfig(code: 'CN', nameCn: '中国', nameLocal: '中国', region: '东亚', langCode: 'zh', langName: '中文', currencyCode: 'CNY', currencySymbol: '¥', timezone: 'UTC+8', timezoneDesc: '北京时间', cnyExchangeRate: 1.0),
    // 东南亚
    CountryConfig(code: 'VN', nameCn: '越南', nameLocal: 'Việt Nam', region: '东南亚', langCode: 'vi', langName: 'Tiếng Việt', currencyCode: 'VND', currencySymbol: '₫', timezone: 'UTC+7', timezoneDesc: '河内时间', cnyExchangeRate: 3520),
    CountryConfig(code: 'MY', nameCn: '马来西亚', nameLocal: 'Malaysia', region: '东南亚', langCode: 'ms', langName: 'Bahasa Melayu', currencyCode: 'MYR', currencySymbol: 'RM', timezone: 'UTC+8', timezoneDesc: '吉隆坡时间', cnyExchangeRate: 0.61),
    // 中亚
    CountryConfig(code: 'UZ', nameCn: '乌兹别克斯坦', nameLocal: 'O\'zbekiston', region: '中亚', langCode: 'uz', langName: 'O\'zbekcha', currencyCode: 'UZS', currencySymbol: 'so\'m', timezone: 'UTC+5', timezoneDesc: '塔什干时间', cnyExchangeRate: 1760),
    CountryConfig(code: 'KZ', nameCn: '哈萨克斯坦', nameLocal: 'Қазақстан', region: '中亚', langCode: 'ru', langName: 'Русский', currencyCode: 'KZT', currencySymbol: '₸', timezone: 'UTC+5', timezoneDesc: '阿斯塔纳时间', cnyExchangeRate: 65),
    // 欧亚
    CountryConfig(code: 'TR', nameCn: '土耳其', nameLocal: 'Türkiye', region: '欧亚', langCode: 'tr', langName: 'Türkçe', currencyCode: 'TRY', currencySymbol: '₺', timezone: 'UTC+3', timezoneDesc: '伊斯坦布尔时间', cnyExchangeRate: 5.0),
    // 欧洲
    CountryConfig(code: 'RU', nameCn: '俄罗斯', nameLocal: 'Россия', region: '欧洲', langCode: 'ru', langName: 'Русский', currencyCode: 'RUB', currencySymbol: '₽', timezone: 'UTC+3', timezoneDesc: '莫斯科时间', cnyExchangeRate: 12.5),
  ];

  static CountryConfig get defaultConfig => all[0]; // 中国

  static CountryConfig fromCode(String code) {
    return all.firstWhere((c) => c.code == code, orElse: () => defaultConfig);
  }

  static Map<String, List<CountryConfig>> get groupedByRegion {
    final map = <String, List<CountryConfig>>{};
    for (final c in all) {
      map.putIfAbsent(c.region, () => []).add(c);
    }
    return map;
  }
}
