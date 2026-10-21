import 'package:intl/intl.dart';

DateTime fromUnixTimestamp(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

int toUnixTimestamp(DateTime dateTime) =>
    dateTime.millisecondsSinceEpoch ~/ 1000;

DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

String formatDayHeader(DateTime date) {
  final now = DateTime.now();
  final today = dateOnly(now);
  final day = dateOnly(date);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return DateFormat('EEEE, d MMMM yyyy').format(date);
}

String formatShortDate(DateTime date) => DateFormat('d MMM yyyy').format(date);

String formatDateTime(DateTime date) =>
    DateFormat('d MMM yyyy, HH:mm').format(date);

String formatTime(DateTime date) => DateFormat('HH:mm').format(date);

String formatMonth(DateTime date) => DateFormat('MMMM yyyy').format(date);

String formatMonthShort(DateTime date) => DateFormat('MMM').format(date);

DateTime startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

DateTime endOfMonth(DateTime date) => DateTime(date.year, date.month + 1, 0, 23, 59, 59);

String sqlDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
