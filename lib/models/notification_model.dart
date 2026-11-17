import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// `notifications/{notificationId}` — created only by Cloud Functions. The
/// recipient may only flip `isRead` (and `readAt`).
class AppNotification {
  const AppNotification({
    required this.notificationId,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.type,
    this.recipientRole = 'faculty',
    this.relatedId,
    this.isRead = false,
    this.createdAt,
  });

  final String notificationId;
  final String recipientId;
  final String recipientRole;
  final String title;
  final String message;
  final NotificationType type;
  final String? relatedId;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromMap(String id, Map<String, dynamic> data) =>
      AppNotification(
        notificationId: id,
        recipientId: readString(data['recipientId']),
        recipientRole: readString(data['recipientRole'], 'faculty'),
        title: readString(data['title']),
        message: readString(data['message']),
        type: NotificationType.parse(data['notificationType'] as String?),
        relatedId: readNullableString(data['relatedId']),
        isRead: data['isRead'] == true,
        createdAt: readDate(data['createdAt']),
      );

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppNotification.fromMap(doc.id, doc.data() ?? const {});
}
