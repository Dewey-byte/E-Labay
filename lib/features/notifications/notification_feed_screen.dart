import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../repositories/notification_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/notification_tile.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/paged_list.dart';
import '../../shared/widgets/state_views.dart';

/// Faculty Office: real-time notification feed.
class NotificationFeedScreen extends ConsumerStatefulWidget {
  const NotificationFeedScreen({super.key});

  @override
  ConsumerState<NotificationFeedScreen> createState() => _NotificationFeedScreenState();
}

class _NotificationFeedScreenState extends ConsumerState<NotificationFeedScreen> {
  bool _unreadOnly = false;

  Future<void> _markAllRead() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await ref.read(notificationRepositoryProvider).markAllAsRead(uid);
      if (mounted) showSuccessSnack(context, 'All notifications marked as read');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: !_unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(unread > 0 ? 'Unread ($unread)' : 'Unread'),
                  selected: _unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedList(
              key: ValueKey(_unreadOnly),
              watch: (ref, limit) => ref.watch(notificationsProvider((limit, _unreadOnly))),
              onRetry: () => ref.invalidate(notificationsProvider),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              spacing: 8,
              itemBuilder: (context, n) => NotificationTile(
                notification: n,
                onTap: () => context.push(AppRoutes.facultyNotification(n.notificationId)),
              ),
              empty: EmptyState(
                icon: Icons.notifications_none,
                title: _unreadOnly ? 'You are all caught up' : 'No notifications yet',
                message: 'Schedule updates and assessment results will appear here.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
