import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/notification_model.dart';
import '../widgets/app_card.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, this.onTap});

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = notification;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      color: n.isRead ? Colors.white : const Color(0xFFF2F8F3),
      borderColor: n.isRead ? null : AppColors.mintSurfaceStrong,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.tint(n.type.color),
              shape: BoxShape.circle,
            ),
            child: Icon(n.type.icon, color: n.type.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(Fmt.relative(n.createdAt), style: theme.textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.message,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  n.type.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: n.type.color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          if (!n.isRead)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 4),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: AppColors.forestGreen, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
