import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/enums.dart';
import '../models/office_model.dart';
import '../models/schedule_model.dart';
import '../models/user_model.dart';

/// Filter + paging parameters for schedule lists. Value-equal so it can be
/// used as a Riverpod family argument.
@immutable
class ScheduleQuery {
  const ScheduleQuery({
    this.officeId,
    this.statuses,
    this.from,
    this.to,
    this.descending = false,
    this.limit = AppConstants.pageSize,
  });

  final String? officeId;
  final List<ScheduleStatus>? statuses;

  /// Inclusive lower bound on `collectionDate`.
  final DateTime? from;

  /// Exclusive upper bound on `collectionDate`.
  final DateTime? to;
  final bool descending;
  final int limit;

  ScheduleQuery copyWith({int? limit}) => ScheduleQuery(
        officeId: officeId,
        statuses: statuses,
        from: from,
        to: to,
        descending: descending,
        limit: limit ?? this.limit,
      );

  @override
  bool operator ==(Object other) =>
      other is ScheduleQuery &&
      other.officeId == officeId &&
      listEquals(other.statuses, statuses) &&
      other.from == from &&
      other.to == to &&
      other.descending == descending &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        officeId,
        statuses == null ? null : Object.hashAll(statuses!),
        from,
        to,
        descending,
        limit,
      );
}

class ScheduleCounts {
  const ScheduleCounts({
    this.total = 0,
    this.pending = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.today = 0,
  });

  final int total;
  final int pending;
  final int completed;
  final int cancelled;
  final int today;
}

/// Collection schedules. Only Collectors may write (enforced by rules);
/// transitions to `completed` and `upcoming` happen in Cloud Functions.
class ScheduleRepository {
  ScheduleRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _schedules =>
      _db.collection(FirestoreCollections.schedules);

  Query<Map<String, dynamic>> _buildQuery(ScheduleQuery q) {
    Query<Map<String, dynamic>> query = _schedules;
    if (q.officeId != null) query = query.where('officeId', isEqualTo: q.officeId);
    final statuses = q.statuses;
    if (statuses != null && statuses.isNotEmpty) {
      query = statuses.length == 1
          ? query.where('status', isEqualTo: statuses.first.value)
          : query.where('status', whereIn: statuses.map((s) => s.value).toList());
    }
    if (q.from != null) {
      query = query.where(
        'collectionDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(q.from!),
      );
    }
    if (q.to != null) {
      query = query.where('collectionDate', isLessThan: Timestamp.fromDate(q.to!));
    }
    return query.orderBy('collectionDate', descending: q.descending).limit(q.limit);
  }

  Stream<List<Schedule>> watchSchedules(ScheduleQuery q) =>
      _buildQuery(q).snapshots().map((s) => s.docs.map(Schedule.fromDoc).toList());

  Stream<Schedule?> watchSchedule(String scheduleId) => _schedules
      .doc(scheduleId)
      .snapshots()
      .map((doc) => doc.exists ? Schedule.fromDoc(doc) : null);

  /// Next pending collection of an office (from the start of today onward).
  Stream<Schedule?> watchNextSchedule(String officeId) {
    final now = DateTime.now();
    return watchSchedules(
      ScheduleQuery(
        officeId: officeId,
        statuses: ScheduleStatus.pending,
        from: DateTime(now.year, now.month, now.day),
        limit: 1,
      ),
    ).map((list) => list.isEmpty ? null : list.first);
  }

  /// Emits whenever any schedule is written; used to refresh aggregate counts.
  Stream<String> watchLatestChange() => _schedules
      .orderBy('updatedAt', descending: true)
      .limit(1)
      .snapshots()
      .map((s) {
        if (s.docs.isEmpty) return 'empty';
        final doc = s.docs.first;
        final ts = doc.data()['updatedAt'];
        return '${doc.id}:${ts is Timestamp ? ts.millisecondsSinceEpoch : 'pending'}';
      });

  Future<ScheduleCounts> fetchCounts() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfTomorrow = startOfToday.add(const Duration(days: 1));

    Future<int> count(Query<Map<String, dynamic>> q) async =>
        (await q.count().get()).count ?? 0;

    final results = await Future.wait([
      count(_schedules),
      count(_schedules.where(
        'status',
        whereIn: ScheduleStatus.pending.map((s) => s.value).toList(),
      )),
      count(_schedules.where('status', isEqualTo: ScheduleStatus.completed.value)),
      count(_schedules.where('status', isEqualTo: ScheduleStatus.cancelled.value)),
      count(_schedules
          .where('collectionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('collectionDate', isLessThan: Timestamp.fromDate(startOfTomorrow))),
    ]);
    return ScheduleCounts(
      total: results[0],
      pending: results[1],
      completed: results[2],
      cancelled: results[3],
      today: results[4],
    );
  }

  Future<String> createSchedule({
    required Office office,
    required AppUser collector,
    required DateTime collectionDate,
    required String collectionTime,
    required String notes,
  }) async {
    try {
      final doc = _schedules.doc();
      await doc.set({
        'scheduleId': doc.id,
        'officeId': office.officeId,
        'officeName': office.officeName,
        'building': office.building,
        'collectorId': collector.uid,
        'collectorName': collector.displayName,
        'collectionDate': Timestamp.fromDate(collectionDate),
        'collectionTime': collectionTime,
        'notes': notes.trim(),
        'status': ScheduleStatus.scheduled.value,
        'reminderSent': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Edits a pending schedule. The office cannot change (cancel and create a
  /// new schedule instead). Changing the date/time marks it `rescheduled`
  /// (and re-arms the reminder); the Cloud Function notifies the office.
  Future<void> updateSchedule(
    Schedule current, {
    required DateTime collectionDate,
    required String collectionTime,
    required String notes,
  }) async {
    final dateChanged = !collectionDate.isAtSameMomentAs(current.collectionDate);
    try {
      await _schedules.doc(current.scheduleId).update({
        'collectionDate': Timestamp.fromDate(collectionDate),
        'collectionTime': collectionTime,
        'notes': notes.trim(),
        if (dateChanged) ...{
          'status': ScheduleStatus.rescheduled.value,
          'previousCollectionDate': Timestamp.fromDate(current.collectionDate),
          'reminderSent': false,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> reschedule(
    Schedule current, {
    required DateTime collectionDate,
    required String collectionTime,
    required String reason,
  }) async {
    try {
      await _schedules.doc(current.scheduleId).update({
        'collectionDate': Timestamp.fromDate(collectionDate),
        'collectionTime': collectionTime,
        'previousCollectionDate': Timestamp.fromDate(current.collectionDate),
        'status': ScheduleStatus.rescheduled.value,
        'statusNote': reason.trim(),
        'reminderSent': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> cancel(String scheduleId, {required String reason}) async {
    try {
      await _schedules.doc(scheduleId).update({
        'status': ScheduleStatus.cancelled.value,
        'statusNote': reason.trim(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> markInProgress(String scheduleId) async {
    try {
      await _schedules.doc(scheduleId).update({
        'status': ScheduleStatus.inProgress.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepository(ref.watch(firestoreProvider)),
);
