import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// `schedules/{scheduleId}` — a garbage collection manually scheduled by a
/// Collector for one faculty office.
///
/// `collectionDate` stores the full scheduled date-time; `collectionTime`
/// keeps the `HH:mm` string for display and auditing.
class Schedule {
  const Schedule({
    required this.scheduleId,
    required this.officeId,
    required this.officeName,
    required this.collectorId,
    required this.collectionDate,
    required this.collectionTime,
    required this.status,
    this.building = '',
    this.collectorName = '',
    this.notes = '',
    this.statusNote,
    this.previousCollectionDate,
    this.collectionId,
    this.pointsAwarded,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String scheduleId;
  final String officeId;
  final String officeName;
  final String building;
  final String collectorId;
  final String collectorName;
  final DateTime collectionDate;
  final String collectionTime;
  final String notes;
  final ScheduleStatus status;

  /// Latest reason given when the schedule was rescheduled or cancelled.
  final String? statusNote;
  final DateTime? previousCollectionDate;

  /// Set by Cloud Functions once the assessment has been submitted.
  final String? collectionId;
  final int? pointsAwarded;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// A pending schedule whose collection day has already passed.
  bool get isOverdue {
    if (!status.isPending || status == ScheduleStatus.inProgress) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return collectionDate.isBefore(today);
  }

  bool get canBeAssessed => status.isPending;
  bool get canBeModified => status.isPending && status != ScheduleStatus.inProgress;

  factory Schedule.fromMap(String id, Map<String, dynamic> data) => Schedule(
        scheduleId: id,
        officeId: readString(data['officeId']),
        officeName: readString(data['officeName'], 'Unknown office'),
        building: readString(data['building']),
        collectorId: readString(data['collectorId']),
        collectorName: readString(data['collectorName']),
        collectionDate: readDate(data['collectionDate']) ?? DateTime.now(),
        collectionTime: readString(data['collectionTime']),
        notes: readString(data['notes']),
        status: ScheduleStatus.parse(data['status'] as String?),
        statusNote: readNullableString(data['statusNote']),
        previousCollectionDate: readDate(data['previousCollectionDate']),
        collectionId: readNullableString(data['collectionId']),
        pointsAwarded:
            data['pointsAwarded'] == null ? null : readInt(data['pointsAwarded']),
        completedAt: readDate(data['completedAt']),
        createdAt: readDate(data['createdAt']),
        updatedAt: readDate(data['updatedAt']),
      );

  factory Schedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Schedule.fromMap(doc.id, doc.data() ?? const {});
}
