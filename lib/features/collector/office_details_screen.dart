import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/office_model.dart';
import '../../models/user_model.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/office_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/office_repository.dart';
import '../../repositories/schedule_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/office_performance.dart';
import '../../shared/components/schedule_tile.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/initials_avatar.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Collector: an office's profile, points, accounts, performance and history.
class OfficeDetailsScreen extends ConsumerStatefulWidget {
  const OfficeDetailsScreen({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<OfficeDetailsScreen> createState() => _OfficeDetailsScreenState();
}

class _OfficeDetailsScreenState extends ConsumerState<OfficeDetailsScreen> {
  int _historyLimit = 5;

  ScheduleQuery get _historyQuery => ScheduleQuery(
        officeId: widget.officeId,
        statuses: ScheduleStatus.history,
        descending: true,
        limit: _historyLimit,
      );

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider(widget.officeId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Office details'),
        actions: [
          IconButton(
            tooltip: 'Edit office',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(AppRoutes.collectorEditOffice(widget.officeId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'office-schedule',
        onPressed: () => context.push(AppRoutes.collectorNewScheduleFor(widget.officeId)),
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('Schedule collection'),
      ),
      body: AsyncValueView(
        value: office,
        onRetry: () => ref.invalidate(officeProvider(widget.officeId)),
        data: (o) {
          if (o == null) {
            return const EmptyState(icon: Icons.apartment, title: 'Office not found');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _Header(office: o),
              const SectionHeader(title: 'Performance'),
              OfficePerformanceSection(office: o),
              SectionHeader(
                title: 'Login accounts',
                actionLabel: 'Add account',
                onAction: () => context.push(AppRoutes.collectorNewAccount(o.officeId)),
              ),
              _Accounts(officeId: o.officeId),
              const SectionHeader(title: 'Collection history'),
              _History(
                query: _historyQuery,
                onLoadMore: () => setState(() => _historyLimit += 10),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.office});

  final Office office;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final board = ref.watch(leaderboardProvider).value;
    final rank = board?.where((r) => r.office.officeId == office.officeId).firstOrNull;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: office.officeName, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(office.officeName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.apartment, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            office.building.isEmpty ? 'No building set' : office.building,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (office.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(office.description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Metric(label: 'Points', value: Fmt.number(office.totalPoints), color: AppColors.forestGreen),
              ),
              Expanded(
                child: _Metric(
                  label: 'Rank',
                  value: rank == null ? '—' : '#${rank.rank}',
                  color: AppColors.gold,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Proper rate',
                  value: Fmt.percent(office.properSegregationRate),
                  color: RateChip.colorFor(office.properSegregationRate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(color: color)),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Accounts extends ConsumerWidget {
  const _Accounts({required this.officeId});

  final String officeId;

  Future<void> _toggle(BuildContext context, WidgetRef ref, AppUser user) async {
    final activate = !user.isActive;
    final ok = await showConfirmDialog(
      context,
      title: activate ? 'Reactivate account?' : 'Deactivate account?',
      message: activate
          ? '${user.displayName} will be able to sign in again.'
          : '${user.displayName} will be signed out and can no longer sign in. '
              'Office records and points are kept.',
      confirmLabel: activate ? 'Reactivate' : 'Deactivate',
      destructive: !activate,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(officeRepositoryProvider).setAccountStatus(uid: user.uid, isActive: activate);
      if (context.mounted) {
        showSuccessSnack(context, activate ? 'Account reactivated' : 'Account deactivated');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(officeAccountsProvider(officeId));
    return AsyncValueView(
      value: accounts,
      compact: true,
      onRetry: () => ref.invalidate(officeAccountsProvider(officeId)),
      data: (list) => list.isEmpty
          ? AppCard(
              child: EmptyState(
                icon: Icons.person_add_alt,
                title: 'No login account',
                message: 'Create an account so this office can receive notifications.',
                compact: true,
                action: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(180, 44)),
                  onPressed: () => context.push(AppRoutes.collectorNewAccount(officeId)),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Create account'),
                ),
              ),
            )
          : AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final u in list)
                    ListTile(
                      leading: InitialsAvatar(name: u.displayName, imageUrl: u.profileImage, size: 40),
                      title: Text(u.displayName),
                      subtitle: Text(u.email),
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: u.isActive ? AppColors.danger : AppColors.forestGreen,
                        ),
                        onPressed: () => _toggle(context, ref, u),
                        child: Text(u.isActive ? 'Deactivate' : 'Reactivate'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.query, required this.onLoadMore});

  final ScheduleQuery query;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(schedulesProvider(query));
    return AsyncValueView(
      value: history,
      compact: true,
      onRetry: () => ref.invalidate(schedulesProvider(query)),
      data: (list) => list.isEmpty
          ? const AppCard(
              child: EmptyState(
                icon: Icons.history,
                title: 'No past collections',
                compact: true,
              ),
            )
          : Column(
              children: [
                for (final s in list) ...[
                  ScheduleTile(
                    schedule: s,
                    showOffice: false,
                    onTap: () => s.collectionId != null
                        ? context.push(AppRoutes.collectorCollection(s.collectionId!))
                        : context.push(AppRoutes.collectorSchedule(s.scheduleId)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (list.length >= query.limit)
                  TextButton(onPressed: onLoadMore, child: const Text('Show more')),
              ],
            ),
    );
  }
}
