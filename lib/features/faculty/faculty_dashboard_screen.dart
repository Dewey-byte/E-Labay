import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/office_model.dart';
import '../../models/schedule_model.dart';
import '../../providers/collection_provider.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/office_provider.dart';
import '../../providers/points_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/collection_tile.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/rate_ring.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Faculty Office home: points, rank, next collection, latest results and
/// segregation performance — all live from Firestore.
class FacultyDashboardScreen extends ConsumerWidget {
  const FacultyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final office = ref.watch(myOfficeProvider);
    return Scaffold(
      body: SafeArea(
        child: AsyncValueView(
          value: office,
          onRetry: () => ref.invalidate(myOfficeProvider),
          data: (o) => o == null
              ? const EmptyState(
                  icon: Icons.apartment,
                  title: 'Office not found',
                  message: 'Your account is not linked to an existing office. Please contact the Collector.',
                )
              : _DashboardBody(office: o),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.office});

  final Office office;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rank = ref.watch(myRankProvider);
    final totalOffices = ref.watch(leaderboardProvider).value?.length;
    final next = ref.watch(nextOfficeScheduleProvider(office.officeId));
    final recent = ref.watch(officeCollectionsProvider((office.officeId, 3)));
    final latestTx = ref.watch(pointTransactionsProvider((office.officeId, 1))).value;
    final latest = latestTx == null || latestTx.isEmpty ? null : latestTx.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Welcome back,', style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
        Text(office.officeName, style: theme.textTheme.headlineSmall),
        if (office.building.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Icon(Icons.apartment, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(office.building, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        const SizedBox(height: 20),

        // Points & rank hero
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(AppRoutes.facultyPoints),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.forestGreen, AppColors.forestGreenDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Accumulated points',
                              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70)),
                          Text(
                            Fmt.number(office.totalPoints),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.emoji_events, color: AppColors.gold),
                          Text(
                            rank == null ? '—' : Fmt.ordinal(rank.rank),
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                          ),
                          Text(
                            totalOffices == null ? 'rank' : 'of $totalOffices',
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.trending_up, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        latest == null
                            ? 'Earn points through proper waste segregation'
                            : 'Latest: ${Fmt.points(latest.pointsAwarded, signed: true)} on ${Fmt.monthDay(latest.effectiveDate)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white70),
                  ],
                ),
              ],
            ),
          ),
        ),

        SectionHeader(
          title: 'Next garbage collection',
          actionLabel: 'All schedules',
          onAction: () => context.go(AppRoutes.facultySchedules),
        ),
        AsyncValueView(
          value: next,
          compact: true,
          onRetry: () => ref.invalidate(nextOfficeScheduleProvider(office.officeId)),
          data: (s) => s == null
              ? const AppCard(
                  child: EmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'No upcoming collection',
                    message: 'You will be notified when the Collector schedules one.',
                    compact: true,
                  ),
                )
              : _NextCollectionCard(schedule: s),
        ),

        SectionHeader(
          title: 'Segregation performance',
          actionLabel: 'Details',
          onAction: () => context.push(AppRoutes.facultyPerformance),
        ),
        AppCard(
          onTap: () => context.push(AppRoutes.facultyPerformance),
          child: Row(
            children: [
              RateRing(rate: office.properSegregationRate, size: 84, label: 'proper'),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final c in WasteCategory.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(c.icon, size: 16, color: c.color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(c.label, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                            ),
                            Text(
                              Fmt.percent(office.statFor(c).rate),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: RateChip.colorFor(office.statFor(c).rate),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SectionHeader(
          title: 'Recent collections',
          actionLabel: 'Points history',
          onAction: () => context.push(AppRoutes.facultyPoints),
        ),
        AsyncValueView(
          value: recent,
          compact: true,
          onRetry: () => ref.invalidate(officeCollectionsProvider((office.officeId, 3))),
          data: (list) => list.isEmpty
              ? const AppCard(
                  child: EmptyState(
                    icon: Icons.history,
                    title: 'No collections yet',
                    message: 'Assessment results will show up here after each collection.',
                    compact: true,
                  ),
                )
              : Column(
                  children: [
                    for (final r in list) ...[
                      CollectionTile(
                        record: r,
                        showOffice: false,
                        onTap: () => context.push(AppRoutes.facultyCollection(r.collectionId)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _NextCollectionCard extends StatelessWidget {
  const _NextCollectionCard({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = schedule;
    return AppCard(
      onTap: () => context.push(AppRoutes.facultySchedule(s.scheduleId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.tint(s.status.color),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.local_shipping_outlined, color: s.status.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.dayLabel(s.collectionDate), style: theme.textTheme.titleMedium),
                    Text(Fmt.time(s.collectionDate), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              StatusChip(status: s.status, overdue: s.isOverdue),
            ],
          ),
          if (s.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.notes, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
