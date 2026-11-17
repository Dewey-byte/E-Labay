import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../providers/collection_provider.dart';
import '../../routes/app_routes.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Collector: confirmation shown after an assessment has been submitted.
/// Reads the server-written collection record (id == schedule id).
class AssessmentSubmittedScreen extends ConsumerWidget {
  const AssessmentSubmittedScreen({super.key, required this.scheduleId});

  final String scheduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(collectionProvider(scheduleId));
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: AsyncValueView(
          value: record,
          onRetry: () => ref.invalidate(collectionProvider(scheduleId)),
          data: (r) {
            if (r == null) return const LoadingView();
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.6, end: 1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.elasticOut,
                    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: const BoxDecoration(color: AppColors.mintSurface, shape: BoxShape.circle),
                      child: const Icon(Icons.task_alt, size: 64, color: AppColors.forestGreen),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Collection completed', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '${r.officeName} has been notified of the assessment result.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                AppCard(
                  child: Column(
                    children: [
                      Text('Points awarded', style: theme.textTheme.labelLarge),
                      Text(
                        '+${r.pointsAwarded}',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: AppColors.forestGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('out of ${r.maxPoints} possible', style: theme.textTheme.bodySmall),
                      const Divider(height: 28),
                      for (final c in WasteCategory.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(c.icon, size: 18, color: c.color),
                              const SizedBox(width: 10),
                              Expanded(child: Text(c.label)),
                              if (r.segregationResults[c] != null)
                                SegregationChip(result: r.segregationResults[c]!),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.pushReplacement(AppRoutes.collectorCollection(r.collectionId)),
                  child: const Text('View assessment details'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.collectorDashboard),
                  child: const Text('Back to dashboard'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
