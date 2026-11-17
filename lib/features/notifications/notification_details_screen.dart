import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../providers/notification_provider.dart';
import '../../repositories/notification_repository.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';
import 'notification_navigation.dart';

/// Faculty Office: a single notification. Opening it marks it as read.
class NotificationDetailsScreen extends ConsumerStatefulWidget {
  const NotificationDetailsScreen({super.key, required this.notificationId});

  final String notificationId;

  @override
  ConsumerState<NotificationDetailsScreen> createState() => _NotificationDetailsScreenState();
}

class _NotificationDetailsScreenState extends ConsumerState<NotificationDetailsScreen> {
  bool _marked = false;

  @override
  Widget build(BuildContext context) {
    final notification = ref.watch(notificationProvider(widget.notificationId));
    final n = notification.value;
    if (n != null && !n.isRead && !_marked) {
      _marked = true;
      ref.read(notificationRepositoryProvider).markAsRead(n.notificationId).ignore();
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: AsyncValueView(
        value: notification,
        onRetry: () => ref.invalidate(notificationProvider(widget.notificationId)),
        data: (n) {
          if (n == null) {
            return const EmptyState(icon: Icons.notifications_off_outlined, title: 'Notification not found');
          }
          final hasTarget = n.relatedId != null && (n.type.relatesToSchedule || n.type.relatesToCollection);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.tint(n.type.color),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(n.type.icon, color: n.type.color, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: TagChip(label: n.type.label, color: n.type.color)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(n.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      n.createdAt == null ? 'Just now' : Fmt.dateTime(n.createdAt!),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(n.message, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              if (hasTarget) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => openNotificationTarget(context, n.type, n.relatedId),
                  icon: Icon(n.type.relatesToSchedule ? Icons.event_note : Icons.fact_check_outlined),
                  label: Text(n.type.relatesToSchedule ? 'View collection schedule' : 'View assessment result'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
