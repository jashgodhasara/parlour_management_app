import 'package:intl/intl.dart';

class DateHelpers {
  static final _dateFormatter = DateFormat('dd MMM yyyy');
  static final _timeFormatter = DateFormat('hh:mm a');
  static final _monthFormatter = DateFormat('MMMM yyyy');
  static final _shortDateFormatter = DateFormat('dd MMM');

  static String formatDate(DateTime date) => _dateFormatter.format(date);
  static String formatTime(DateTime dateTime) => _timeFormatter.format(dateTime);
  static String formatMonth(DateTime date) => _monthFormatter.format(date);
  static String formatShortDate(DateTime date) => _shortDateFormatter.format(date);

  static DateTime weekStart(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static DateTime weekEnd(DateTime date) {
    final sunday = weekStart(date).add(const Duration(days: 6));
    return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);
}
