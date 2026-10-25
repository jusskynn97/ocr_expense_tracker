import 'package:intl/intl.dart';

/// Tiện ích ngày tháng dùng xuyên suốt app.
class AppDateFormatter {
  const AppDateFormatter._();

  static const List<String> _weekdayShort = <String>[
    'Th 2',
    'Th 3',
    'Th 4',
    'Th 5',
    'Th 6',
    'Th 7',
    'CN',
  ];

  static const List<String> _weekdayLong = <String>[
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ nhật',
  ];

  static String date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

  static String monthYear(DateTime value) => DateFormat('MM/yyyy').format(value);

  static String monthName(DateTime value) =>
      'Tháng ${DateFormat('MM').format(value)}, ${value.year}';

  static String weekdayShort(DateTime value) => _weekdayShort[value.weekday - 1];

  static String weekdayLong(DateTime value) => _weekdayLong[value.weekday - 1];

  /// Nhãn nhóm danh sách: "Hôm nay", "Hôm qua" hoặc "Thứ Ba, 21/10".
  static String dayHeader(DateTime value) {
    final DateTime today = startOfDay(DateTime.now());
    final DateTime target = startOfDay(value);
    final int diff = today.difference(target).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return '${weekdayLong(value)}, ${DateFormat('dd/MM').format(value)}';
  }

  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  /// Thứ Hai được xem là đầu tuần.
  static DateTime startOfWeek(DateTime value) =>
      startOfDay(value).subtract(Duration(days: value.weekday - 1));

  static DateTime startOfMonth(DateTime value) => DateTime(value.year, value.month);

  static DateTime endOfMonth(DateTime value) =>
      DateTime(value.year, value.month + 1, 0, 23, 59, 59, 999);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
