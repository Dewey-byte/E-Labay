import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../core/utils/formatters.dart';
import '../models/enums.dart';
import '../models/office_model.dart';
import '../models/schedule_model.dart';
import '../models/user_model.dart';
import 'notification_repository.dart';

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

/// Collection schedules. Only Collectors may write (enforced by security
/// rules). Every change and its office notifications commit atomically.
class ScheduleRepository {
  ScheduleRepository(this._db, this._notices);

  final FirebaseFirestore _db;
  final NotificationRepository _notices;

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

  String _when(DateTime d) => '${Fmt.date(d)} at ${Fmt.time(d)}';

  String _withNotes(String message, String notes) =>
      notes.trim().isEmpty ? message : '$message Instructions: ${notes.trim()}';

  /// Creates a schedule and notifies the office in the same atomic write.
  Future<String> createSchedule({
    required Office office,
    required AppUser collector,
    required DateTime collectionDate,
    required String collectionTime,
    required String notes,
  }) async {
    try {
      final recipients = await _notices.officeRecipients(office.officeId);
      final doc = _schedules.doc();
      final batch = _db.batch();
      batch.set(doc, {
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
      _notices.addNotices(
        batch.set,
        recipients: recipients,
        officeId: office.officeId,
        notice: OfficeNotice(
          key: 'created_${doc.id}',
          type: NotificationType.scheduleCreated,
          title: 'New garbage collection scheduled',
          message: _withNotes('A garbage collection is scheduled for ${_when(collectionDate)}.', notes),
          scheduleId: doc.id,
        ),
      );
      await batch.commit();
      return doc.id;
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Edits a pending schedule. The office cannot change (cancel and create a
  /// new schedule instead). Changing the date/time marks it `rescheduled`
  /// and re-arms the reminder. The office is notified of the change.
  Future<void> updateSchedule(
    Schedule current, {
    required DateTime collectionDate,
    required String collectionTime,
    required String notes,
  }) async {
    final dateChanged = !collectionDate.isAtSameMomentAs(current.collectionDate);
    final notesChanged = notes.trim() != current.notes.trim();
    try {
      final recipients = await _notices.officeRecipients(current.officeId);
      final batch = _db.batch();
      batch.update(_schedules.doc(current.scheduleId), {
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
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (dateChanged) {
        _notices.addNotices(
          batch.set,
          recipients: recipients,
          officeId: current.officeId,
          notice: OfficeNotice(
            key: 'rescheduled_${current.scheduleId}_$stamp',
            type: NotificationType.scheduleRescheduled,
            title: 'Garbage collection rescheduled',
            message: _withNotes(
              'Your collection has been moved from ${_when(current.collectionDate)} to ${_when(collectionDate)}.',
              notes,
            ),
            scheduleId: current.scheduleId,
          ),
        );
      } else if (notesChanged) {
        _notices.addNotices(
          batch.set,
          recipients: recipients,
          officeId: current.officeId,
          notice: OfficeNotice(
            key: 'updated_${current.scheduleId}_$stamp',
            type: NotificationType.scheduleUpdated,
            title: 'Collection instructions updated',
            message: _withNotes(
              'The Collector updated the instructions for your collection on ${_when(collectionDate)}.',
              notes,
            ),
            scheduleId: current.scheduleId,
          ),
        );
      }
      await batch.commit();
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
      final recipients = await _notices.officeRecipients(current.officeId);
      final batch = _db.batch();
      batch.update(_schedules.doc(current.scheduleId), {
        'collectionDate': Timestamp.fromDate(collectionDate),
        'collectionTime': collectionTime,
        'previousCollectionDate': Timestamp.fromDate(current.collectionDate),
        'status': ScheduleStatus.rescheduled.value,
        'statusNote': reason.trim(),
        'reminderSent': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _notices.addNotices(
        batch.set,
        recipients: recipients,
        officeId: current.officeId,
        notice: OfficeNotice(
          key: 'rescheduled_${current.scheduleId}_${DateTime.now().millisecondsSinceEpoch}',
          type: NotificationType.scheduleRescheduled,
          title: 'Garbage collection rescheduled',
          message: 'Your collection has been moved from ${_when(current.collectionDate)} '
              'to ${_when(collectionDate)}. Reason: ${reason.trim()}',
          scheduleId: current.scheduleId,
        ),
      );
      await batch.commit();
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> cancel(Schedule current, {required String reason}) async {
    try {
      final recipients = await _notices.officeRecipients(current.officeId);
      final batch = _db.batch();
      batch.update(_schedules.doc(current.scheduleId), {
        'status': ScheduleStatus.cancelled.value,
        'statusNote': reason.trim(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _notices.addNotices(
        batch.set,
        recipients: recipients,
        officeId: current.officeId,
        notice: OfficeNotice(
          key: 'cancelled_${current.scheduleId}',
          type: NotificationType.scheduleCancelled,
          title: 'Garbage collection cancelled',
          message: 'The collection scheduled for ${_when(current.collectionDate)} has been cancelled. '
              'Reason: ${reason.trim()}',
          scheduleId: current.scheduleId,
        ),
      );
      await batch.commit();
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

  /// Sends reminders for pending collections due within the next 24 hours
  /// and marks them `upcoming`, once per schedule. Runs whenever the
  /// Collector opens the app (on Blaze the optional scheduled function also
  /// runs it every 30 minutes). Returns how many reminders were sent.
  Future<int> sendDueReminders() async {
    final now = DateTime.now();
    final due = await _schedules
        .where('status', whereIn: [ScheduleStatus.scheduled.value, ScheduleStatus.rescheduled.value])
        .where('collectionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        // A few minutes of margin for clock differences with the server.
        .where('collectionDate', isLessThanOrEqualTo: Timestamp.fromDate(now.add(const Duration(hours: 23, minutes: 50))))
        .get();
    var sent = 0;
    for (final doc in due.docs) {
      if (doc.data()['reminderSent'] == true) continue;
      try {
        final officeId = doc.data()['officeId'] as String;
        final recipients = await _notices.officeRecipients(officeId);
        final didSend = await _db.runTransaction<bool>((tx) async {
          final snap = await tx.get(doc.reference);
          final data = snap.data();
          if (data == null || data['reminderSent'] == true) return false;
          final fresh = Schedule.fromDoc(snap);
          if (fresh.status != ScheduleStatus.scheduled && fresh.status != ScheduleStatus.rescheduled) {
            return false;
          }
          tx.update(doc.reference, {
            'status': ScheduleStatus.upcoming.value,
            'reminderSent': true,
            'reminderSentAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _notices.addNotices(
            tx.set,
            recipients: recipients,
            officeId: fresh.officeId,
            notice: OfficeNotice(
              // Same id format as the optional Blaze reminder function.
              key: 'reminder_${fresh.scheduleId}_${fresh.collectionDate.millisecondsSinceEpoch}',
              type: NotificationType.scheduleReminder,
              title: 'Upcoming garbage collection',
              message: _withNotes(
                'Reminder: your garbage collection is on ${_when(fresh.collectionDate)}. '
                'Please have your waste properly segregated.',
                fresh.notes,
              ),
              scheduleId: fresh.scheduleId,
            ),
          );
          return true;
        });
        if (didSend) sent++;
      } catch (e) {
        debugPrint('Reminder for ${doc.id} skipped: $e');
      }
    }
    return sent;
  }
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepository(ref.watch(firestoreProvider), ref.watch(notificationRepositoryProvider)),
);
