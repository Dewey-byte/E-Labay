import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ranking.dart';
import '../../providers/auth_provider.dart';
import '../../providers/leaderboard_provider.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/initials_avatar.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Campus-wide leaderboard ranked by accumulated points. Updates live.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider);
    final myOfficeId = ref.watch(currentUserProvider)?.officeId;
    final mine = ref.watch(myRankProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Campus leaderboard')),
      body: AsyncValueView(
        value: board,
        onRetry: () => ref.invalidate(leaderboardProvider),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'No offices yet',
              message: 'Rankings appear once faculty offices are registered.',
            );
          }
          final podium = list.take(3).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (mine != null) ...[
                _MyRankCard(entry: mine, total: list.length),
                const SizedBox(height: 16),
              ],
              _Podium(entries: podium, myOfficeId: myOfficeId),
              const SizedBox(height: 20),
              Text('Full ranking', style: Theme.of(context).textTheme.titleMedium),
              Text(
                'Ranked by accumulated points. Offices with equal points share a rank.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              for (final entry in list) ...[
                _RankRow(entry: entry, highlight: entry.office.officeId == myOfficeId),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

Color _medalColor(int rank) => switch (rank) {
      1 => AppColors.gold,
      2 => AppColors.silver,
      3 => AppColors.bronze,
      _ => AppColors.textMuted,
    };

class _MyRankCard extends StatelessWidget {
  const _MyRankCard({required this.entry, required this.total});

  final RankedOffice entry;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.forestGreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              '#${entry.rank}',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your office', style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70)),
                Text(
                  '${Fmt.ordinal(entry.rank)} of $total offices',
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          Text(
            Fmt.points(entry.office.totalPoints),
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.myOfficeId});

  final List<RankedOffice> entries;
  final String? myOfficeId;

  @override
  Widget build(BuildContext context) {
    // Display order: 2nd, 1st, 3rd.
    final order = <(RankedOffice, double)>[
      if (entries.length > 1) (entries[1], 92),
      (entries[0], 120),
      if (entries.length > 2) (entries[2], 72),
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (entry, height) in order)
            Expanded(
              child: _PodiumColumn(
                entry: entry,
                height: height,
                isMine: entry.office.officeId == myOfficeId,
              ),
            ),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({required this.entry, required this.height, required this.isMine});

  final RankedOffice entry;
  final double height;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _medalColor(entry.rank);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.rank == 1) const Icon(Icons.workspace_premium, color: AppColors.gold, size: 28),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
            child: InitialsAvatar(name: entry.office.officeName, size: entry.rank == 1 ? 58 : 48, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            entry.office.officeName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isMine ? AppColors.forestGreen : null,
              fontWeight: isMine ? FontWeight.w800 : null,
            ),
          ),
          Text(Fmt.points(entry.office.totalPoints), style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Container(
            height: height,
            width: double.infinity,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.tint(color, 0.45), AppColors.tint(color, 0.15)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              '${entry.rank}',
              style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.highlight});

  final RankedOffice entry;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = entry.office;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: highlight ? AppColors.mintSurface : null,
      borderColor: highlight ? AppColors.forestGreen : null,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: entry.rank <= 3
                ? Icon(Icons.emoji_events, color: _medalColor(entry.rank))
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
                  ),
          ),
          const SizedBox(width: 8),
          InitialsAvatar(name: o.officeName, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(o.officeName,
                          style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 6),
                      const TagChip(label: 'You', color: AppColors.forestGreen),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    RateChip(rate: o.properSegregationRate),
                    TagChip(
                      label: '${o.totalCollections} collections',
                      color: AppColors.info,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.number(o.totalPoints),
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.forestGreen)),
              Text('pts', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
