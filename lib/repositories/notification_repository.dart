import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/enums.dart';
import '../models/notification_model.dart';

/// Writes a document as part of a batch or transaction.
typedef DocWriter = void Function(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data);

/// A notification to deliver to every active account of an office.
class OfficeNotice {
  const OfficeNotice({
    required this.key,
    required this.type,
    required this.title,
    required this.message,
    required this.scheduleId,
  });

  /// Unique per event; each recipient's document id is `{key}_{uid}`, which
  /// makes retries idempotent.
  final String key;
  final NotificationType type;
  final String title;
  final String message;

  /// Related schedule (collection records share the schedule id).
  final String scheduleId;
}

/// In-app notifications. The Collector's app creates them in the same atomic
/// write as the schedule change or assessment they describe (validated by
/// security rules); recipients can only mark them as read.
class NotificationRepository {
  NotificationRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection(FirestoreCollections.notifications);

  /// Active Faculty Office accounts linked to [officeId] (Collectors only).
  Future<List<String>> officeRecipients(String officeId) async {
    final snap = await _db
        .collection(FirestoreCollections.users)
        .where('officeId', isEqualTo: officeId)
        .where('role', isEqualTo: UserRole.faculty.value)
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Adds one notification per recipient to a batch or transaction.
  void addNotices(
    DocWriter write, {
    required List<String> recipients,
    required String officeId,
    required OfficeNotice notice,
  }) {
    for (final uid in recipients) {
      final id = '${notice.key}_$uid';
      write(_notifications.doc(id), {
        'notificationId': id,
        'recipientId': uid,
        'recipientRole': UserRole.faculty.value,
        'officeId': officeId,
        'title': notice.title,
        'message': _clip(notice.message, 1000),
        'notificationType': notice.type.value,
        'relatedId': notice.scheduleId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  Stream<List<AppNotification>> watchNotifications(
    String uid, {
    int limit = AppConstants.pageSize,
    bool unreadOnly = false,
  }) {
    Query<Map<String, dynamic>> q = _notifications.where('recipientId', isEqualTo: uid);
    if (unreadOnly) q = q.where('isRead', isEqualTo: false);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromDoc).toList());
  }

  /// Unread count (capped at 100 to keep the listener cheap).
  Stream<int> watchUnreadCount(String uid) => _notifications
      .where('recipientId', isEqualTo: uid)
      .where('isRead', isEqualTo: false)
      .limit(100)
      .snapshots()
      .map((s) => s.size);

  Stream<AppNotification?> watchNotification(String id) => _notifications
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? AppNotification.fromDoc(doc) : null);

  Future<void> markAsRead(String id) async {
    try {
      await _notifications.doc(id).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> markAllAsRead(String uid) async {
    try {
      final unread = await _notifications
          .where('recipientId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .limit(400)
          .get();
      if (unread.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(firestoreProvider)),
);
