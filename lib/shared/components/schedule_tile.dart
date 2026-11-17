import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/schedule_model.dart';
import '../widgets/app_card.dart';
import '../widgets/status_chip.dart';

/// List tile for a collection schedule.
class ScheduleTile extends StatelessWidget {
  const ScheduleTile({
    super.key,
    required this.schedule,
    this.onTap,
    this.showOffice = true,
  });

  final Schedule schedule;
  final VoidCallback? onTap;
  final bool showOffice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = schedule;
    final color = s.isOverdue ? AppColors.danger : s.status.color;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.tint(color, 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  Fmt.weekday(s.collectionDate).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${s.collectionDate.day}',
                  style: theme.textTheme.titleLarge?.copyWith(color: color, height: 1.1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showOffice ? s.officeName : Fmt.date(s.collectionDate),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        showOffice
                            ? '${Fmt.monthDay(s.collectionDate)} · ${Fmt.time(s.collectionDate)}'
                            : Fmt.time(s.collectionDate),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showOffice && s.building.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.apartment, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          s.building,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusChip(status: s.status, overdue: s.isOverdue),
                    if (s.pointsAwarded != null) ...[
                      const SizedBox(width: 6),
                      TagChip(
                        label: Fmt.points(s.pointsAwarded!, signed: true),
                        color: AppColors.gold,
                        icon: Icons.emoji_events_outlined,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
