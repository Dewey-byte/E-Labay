import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';
import 'auth_provider.dart';

/// Notification feed of the signed-in user; argument is `(limit, unreadOnly)`.
final notificationsProvider =
    StreamProvider.autoDispose.family<List<AppNotification>, (int, bool)>((ref, args) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(notificationRepositoryProvider)
      .watchNotifications(uid, limit: args.$1, unreadOnly: args.$2);
});

final unreadNotificationCountProvider = StreamProvider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCount(uid);
});

final notificationProvider = StreamProvider.autoDispose.family<AppNotification?, String>(
  (ref, id) => ref.watch(notificationRepositoryProvider).watchNotification(id),
);
