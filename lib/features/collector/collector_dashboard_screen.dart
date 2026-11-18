import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/schedule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collection_provider.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/office_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/schedule_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/charts.dart';
import '../../shared/components/collection_tile.dart';
import '../../shared/components/schedule_tile.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/stat_card.dart';
import '../../shared/widgets/state_views.dart';

class CollectorDashboardScreen extends ConsumerWidget {
  const CollectorDashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final offices = ref.watch(officesProvider);
    final counts = ref.watch(scheduleCountsProvider);
    final today = ref.watch(todaySchedulesProvider);
    final upcoming = ref.watch(upcomingSchedulesProvider);
    final recent = ref.watch(recentCollectionsProvider);
    final weekly = ref.watch(weeklyCollectionsProvider);
    final theme = Theme.of(context);
    final c = counts.value ?? const ScheduleCounts();
    String count(int v) => counts.hasValue ? Fmt.number(v) : '…';

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard-new-schedule',
        onPressed: () => context.push(AppRoutes.collectorNewSchedule),
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(scheduleCountsProvider);
            await ref.read(scheduleCountsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('${_greeting()},', style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
              Text(user?.displayName ?? 'Collector', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(Fmt.date(DateTime.now()), style: theme.textTheme.bodySmall),
              const SizedBox(height: 20),

              // Today's collections
              _TodayCard(
                count: count(c.today),
                schedules: today,
                onSeeAll: () => context.go(AppRoutes.collectorSchedules),
              ),
              const SizedBox(height: 12),

              StatGrid(
                children: [
                  StatCard(
                    icon: Icons.apartment,
                    label: 'Faculty offices',
                    value: offices.hasValue ? Fmt.number(offices.value!.length) : '…',
                    color: AppColors.forestGreen,
                    onTap: () => context.go(AppRoutes.collectorOffices),
                  ),
                  StatCard(
                    icon: Icons.event_note_outlined,
                    label: 'Total scheduled',
                    value: count(c.total),
                    color: AppColors.info,
                    onTap: () => context.go(AppRoutes.collectorSchedules),
                  ),
                  StatCard(
                    icon: Icons.pending_actions_outlined,
                    label: 'Pending',
                    value: count(c.pending),
                    color: AppColors.warning,
                    onTap: () => context.go(AppRoutes.collectorSchedules),
                  ),
                  StatCard(
                    icon: Icons.task_alt,
                    label: 'Completed',
                    value: count(c.completed),
                    color: AppColors.success,
                    onTap: () => context.go(AppRoutes.collectorHistory),
                  ),
                ],
              ),

              const SectionHeader(title: 'Collection statistics'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Completed collections · last 7 days', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 16),
                    AsyncValueView(
                      value: weekly,
                      compact: true,
                      onRetry: () => ref.invalidate(weeklyCollectionsProvider),
                      data: (list) => WeeklyCollectionsChart(collections: list),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('Schedules by status', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    DonutChartWithLegend(
                      centerLabel: 'total',
                      segments: [
                        DonutSegment('Pending', c.pending, AppColors.warning),
                        DonutSegment('Completed', c.completed, AppColors.success),
                        DonutSegment('Cancelled', c.cancelled, AppColors.danger),
                      ],
                    ),
                  ],
                ),
              ),

              SectionHeader(
                title: 'Campus leaderboard',
                actionLabel: 'Full ranking',
                onAction: () => context.push(AppRoutes.collectorLeaderboard),
              ),
              const _LeaderboardPreview(),

              SectionHeader(
                title: 'Upcoming collections',
                actionLabel: 'See all',
                onAction: () => context.go(AppRoutes.collectorSchedules),
              ),
              AsyncValueView(
                value: upcoming,
                compact: true,
                onRetry: () => ref.invalidate(upcomingSchedulesProvider),
                data: (list) => list.isEmpty
                    ? const AppCard(
                        child: EmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'Nothing scheduled',
                          message: 'Create a collection schedule to get started.',
                          compact: true,
                        ),
                      )
                    : Column(
                        children: [
                          for (final s in list) ...[
                            ScheduleTile(
                              schedule: s,
                              onTap: () => context.push(AppRoutes.collectorSchedule(s.scheduleId)),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),

              SectionHeader(
                title: 'Recent collection activity',
                actionLabel: 'History',
                onAction: () => context.go(AppRoutes.collectorHistory),
              ),
              AsyncValueView(
                value: recent,
                compact: true,
                onRetry: () => ref.invalidate(recentCollectionsProvider),
                data: (list) => list.isEmpty
                    ? const AppCard(
                        child: EmptyState(
                          icon: Icons.history,
                          title: 'No collections yet',
                          message: 'Completed assessments will appear here.',
                          compact: true,
                        ),
                      )
                    : Column(
                        children: [
                          for (final r in list) ...[
                            CollectionTile(
                              record: r,
                              onTap: () => context.push(AppRoutes.collectorCollection(r.collectionId)),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top three offices by points; tapping one opens its details.
class _LeaderboardPreview extends ConsumerWidget {
  const _LeaderboardPreview();

  static const _medals = [AppColors.gold, AppColors.silver, AppColors.bronze];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider);
    final theme = Theme.of(context);
    return AsyncValueView(
      value: board,
      compact: true,
      onRetry: () => ref.invalidate(leaderboardProvider),
      data: (list) {
        if (list.isEmpty) {
          return const AppCard(
            child: EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'No offices ranked yet',
              message: 'Rankings appear once offices are registered.',
              compact: true,
            ),
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final entry in list.take(3))
                ListTile(
                  onTap: () => context.push(AppRoutes.collectorOffice(entry.office.officeId)),
                  leading: SizedBox(
                    width: 40,
                    child: Icon(
                      Icons.emoji_events,
                      color: entry.rank <= 3 ? _medals[entry.rank - 1] : AppColors.textMuted,
                    ),
                  ),
                  title: Text(
                    entry.office.officeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    '${Fmt.ordinal(entry.rank)} · ${Fmt.percent(entry.office.properSegregationRate)} proper',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Text(
                    Fmt.points(entry.office.totalPoints),
                    style: theme.textTheme.titleSmall?.copyWith(color: AppColors.forestGreen),
                  ),
                ),
              if (list.length > 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: Text(
                    '${list.length - 3} more office${list.length - 3 == 1 ? '' : 's'} in the full ranking',
                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.count, required this.schedules, required this.onSeeAll});

  final String count;
  final AsyncValue<List<Schedule>> schedules;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = schedules.value ?? const <Schedule>[];
    final pending = list.where((s) => s.status.isPending).toList();
    return Container(
      padding: const EdgeInsets.all(18),
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
              const Icon(Icons.today, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Today's collections",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70),
                ),
              ),
              InkWell(
                onTap: onSeeAll,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.arrow_forward, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          Text(
            pending.isEmpty
                ? 'No pending pickups left today'
                : '${pending.length} still to collect',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final s in pending.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        Fmt.time(s.collectionDate),
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.officeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
