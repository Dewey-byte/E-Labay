import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/notification_model.dart';

/// In-app notification feed. Notifications are created by Cloud Functions and
/// synchronised through Firestore; recipients can only mark them as read.
class NotificationRepository {
  NotificationRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection(FirestoreCollections.notifications);

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
