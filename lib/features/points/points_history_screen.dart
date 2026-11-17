import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/point_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/office_provider.dart';
import '../../providers/points_provider.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/paged_list.dart';
import '../../shared/widgets/state_views.dart';

/// Faculty Office: total points and the point transaction ledger.
class PointsHistoryScreen extends ConsumerWidget {
  const PointsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final officeId = ref.watch(currentUserProvider)?.officeId;
    final office = ref.watch(myOfficeProvider).value;
    final theme = Theme.of(context);
    if (officeId == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Points history')),
      body: PagedList<PointTransaction>(
        watch: (ref, limit) => ref.watch(pointTransactionsProvider((officeId, limit))),
        onRetry: () => ref.invalidate(pointTransactionsProvider),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        header: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.forestGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total accumulated points',
                              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70)),
                          Text(
                            office == null ? '…' : Fmt.number(office.totalPoints),
                            style: theme.textTheme.displaySmall
                                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            office == null ? '' : 'from ${office.totalCollections} assessed collections',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.emoji_events, color: AppColors.gold, size: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
        itemBuilder: (context, tx) => _TransactionTile(
          tx: tx,
          onTap: () => context.push(AppRoutes.facultyCollection(tx.collectionId)),
        ),
        empty: const EmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'No points yet',
          message: 'Points are awarded after each collection based on how well your office segregates waste.',
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx, required this.onTap});

  final PointTransaction tx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.gold),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_task, color: AppColors.gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Collection assessment', style: theme.textTheme.titleSmall),
                    Text(Fmt.dateTime(tx.effectiveDate), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                Fmt.points(tx.pointsAwarded, signed: true),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tx.pointsAwarded > 0 ? AppColors.forestGreen : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${tx.properCount} of ${tx.applicableCount} categories properly segregated'
            '${tx.collectorName.isNotEmpty ? ' · by ${tx.collectorName}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          if (tx.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('"${tx.remarks}"', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ),
          ],
        ],
      ),
    );
  }
}
