import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts a Firestore value (Timestamp / DateTime / millis) to a local DateTime.
DateTime? readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String readString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? readNullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic> readMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> readStringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const <String>[];
