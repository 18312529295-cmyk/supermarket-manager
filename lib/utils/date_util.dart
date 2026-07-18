import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class DateUtil {
  static tz.Location? _tashkent;

  static void initialize() {
    tz_data.initializeTimeZones();
    _tashkent = tz.getLocation('Asia/Tashkent');
  }

  static DateTime nowInTashkent() {
    if (_tashkent == null) initialize();
    return tz.TZDateTime.now(_tashkent!);
  }

  static DateTime convertToTashkent(DateTime dateTime) {
    if (_tashkent == null) initialize();
    return tz.TZDateTime.from(dateTime, _tashkent!);
  }

  static String formatDate(DateTime dateTime, {bool includeTime = false}) {
    final dt = convertToTashkent(dateTime);
    final year = dt.year.toString();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');

    if (!includeTime) {
      return '$year-$month-$day';
    }

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  static String formatDateTime(DateTime dateTime) {
    return formatDate(dateTime, includeTime: true);
  }

  static String formatRelative(DateTime dateTime) {
    final now = nowInTashkent();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return formatDate(dateTime);
  }

  static int? daysBetween(DateTime? from, DateTime? to) {
    if (from == null || to == null) return null;
    return to.difference(from).inDays;
  }

  static DateTime startOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  static DateTime endOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day, 23, 59, 59);
  }

  static DateTime startOfWeek(DateTime dateTime) {
    final weekday = dateTime.weekday;
    return startOfDay(dateTime.subtract(Duration(days: weekday - 1)));
  }

  static DateTime startOfMonth(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, 1);
  }
}
