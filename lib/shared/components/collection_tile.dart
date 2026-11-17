import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/collection_model.dart';
import '../widgets/app_card.dart';
import '../widgets/status_chip.dart';

/// Activity tile for a completed collection.
class CollectionTile extends StatelessWidget {
  const CollectionTile({super.key, required this.record, this.onTap, this.showOffice = true});

  final CollectionRecord record;
  final VoidCallback? onTap;
  final bool showOffice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.success),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.task_alt, color: AppColors.success),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showOffice ? r.officeName : 'Collection completed',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${Fmt.dateTime(r.effectiveDate)}'
                  '${r.collectorName.isNotEmpty ? ' · ${r.collectorName}' : ''}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                RateChip(rate: r.properRate),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${r.pointsAwarded}',
                style: theme.textTheme.titleLarge?.copyWith(color: AppColors.forestGreen),
              ),
              Text('points', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
