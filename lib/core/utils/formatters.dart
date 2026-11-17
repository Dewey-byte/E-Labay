import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Date, time and number formatting helpers used across the UI.
class Fmt {
  Fmt._();

  static final _date = DateFormat('EEE, MMM d, y');
  static final _shortDate = DateFormat('MMM d, y');
  static final _monthDay = DateFormat('MMM d');
  static final _time = DateFormat('h:mm a');
  static final _weekday = DateFormat('EEE');

  static String date(DateTime d) => _date.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);
  static String monthDay(DateTime d) => _monthDay.format(d);
  static String weekday(DateTime d) => _weekday.format(d);
  static String time(DateTime d) => _time.format(d);
  static String dateTime(DateTime d) => '${_shortDate.format(d)} · ${_time.format(d)}';

  /// "Today", "Tomorrow", "Yesterday" or a short date.
  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return _date.format(d);
  }

  /// "Today · 2:30 PM"
  static String schedule(DateTime d) => '${dayLabel(d)} · ${time(d)}';

  /// "just now", "5m ago", "3h ago", "2d ago" or a short date.
  static String relative(DateTime? d) {
    if (d == null) return 'just now';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _shortDate.format(d);
  }

  static String percent(double? value, {int decimals = 0}) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(decimals)}%';

  static String number(num value) => NumberFormat.decimalPattern().format(value);

  static String points(int value, {bool signed = false}) =>
      '${signed && value > 0 ? '+' : ''}${number(value)} pts';

  static String ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// `TimeOfDay` -> `HH:mm` (24h, stored in Firestore).
  static String timeOfDayToStorage(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
