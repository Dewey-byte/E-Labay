import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/office_model.dart';
import '../../providers/collection_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/rate_ring.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_card.dart';
import '../widgets/state_views.dart';
import 'charts.dart';

/// Number of recent collections plotted in the performance trend.
const kTrendWindow = 12;

/// Performance overview of an office: totals, average score, proper
/// segregation rate, historical trend and per-category breakdown. Used by the
/// Faculty "Performance" screen and the Collector's office details.
class OfficePerformanceSection extends ConsumerWidget {
  const OfficePerformanceSection({super.key, required this.office});

  final Office office;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(officeCollectionsProvider((office.officeId, kTrendWindow)));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(
              icon: Icons.task_alt,
              label: 'Completed collections',
              value: Fmt.number(office.totalCollections),
              color: AppColors.success,
            ),
            StatCard(
              icon: Icons.emoji_events_outlined,
              label: 'Total points earned',
              value: Fmt.number(office.totalPoints),
              color: AppColors.gold,
            ),
            StatCard(
              icon: Icons.speed,
              label: 'Average score',
              value: office.averageScore == null
                  ? '—'
                  : office.averageScore!.toStringAsFixed(1),
              caption: 'points per collection',
              color: AppColors.info,
            ),
            StatCard(
              icon: Icons.eco_outlined,
              label: 'Proper segregation rate',
              value: Fmt.percent(office.properSegregationRate),
              caption: '${office.totalProperSegregations} of ${office.totalAssessments} categories',
              color: AppColors.forestGreen,
            ),
          ],
        ),
        const SectionHeader(title: 'Points trend'),
        AppCard(
          child: AsyncValueView(
            value: recent,
            compact: true,
            onRetry: () => ref.invalidate(officeCollectionsProvider((office.officeId, kTrendWindow))),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.show_chart,
                    title: 'No collections yet',
                    message: 'The trend appears after the first assessed collection.',
                    compact: true,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Points earned in the last ${list.length} collection${list.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      PointsTrendChart(collections: list),
                    ],
                  ),
          ),
        ),
        const SectionHeader(title: 'Segregation by category'),
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  RateRing(rate: office.properSegregationRate, size: 76, label: 'overall'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      office.totalAssessments == 0
                          ? 'No category assessments yet.'
                          : 'Share of assessed waste categories that were properly segregated. '
                              '"Not applicable" categories are excluded.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              CategoryBreakdown(office: office),
            ],
          ),
        ),
      ],
    );
  }
}
