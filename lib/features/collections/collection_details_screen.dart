import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../providers/collection_provider.dart';
import '../../shared/components/photo_viewer.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/info_row.dart';
import '../../shared/widgets/rate_ring.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/status_chip.dart';

/// Points and assessment details of a completed collection (both roles;
/// Firestore rules limit Faculty Offices to their own records).
class CollectionDetailsScreen extends ConsumerWidget {
  const CollectionDetailsScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(collectionProvider(collectionId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment details')),
      body: AsyncValueView(
        value: record,
        onRetry: () => ref.invalidate(collectionProvider(collectionId)),
        data: (r) {
          if (r == null) {
            return const EmptyState(icon: Icons.search_off, title: 'Assessment not found');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              AppCard(
                child: Row(
                  children: [
                    RateRing(rate: r.properRate, size: 80, label: 'proper'),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Points awarded', style: theme.textTheme.labelLarge),
                          Text(
                            '+${r.pointsAwarded}',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: AppColors.forestGreen,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('out of ${r.maxPoints} possible', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    InfoRow(icon: Icons.apartment, label: 'Faculty office', value: r.officeName),
                    InfoRow(icon: Icons.event_available, label: 'Collected', value: Fmt.dateTime(r.effectiveDate)),
                    if (r.scheduledDate != null)
                      InfoRow(icon: Icons.event_outlined, label: 'Scheduled for', value: Fmt.dateTime(r.scheduledDate!)),
                    InfoRow(
                      icon: Icons.person_outline,
                      label: 'Assessed by',
                      value: r.collectorName.isEmpty ? 'Collector' : r.collectorName,
                    ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Segregation assessment'),
              AppCard(
                child: Column(
                  children: [
                    for (final c in WasteCategory.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.tint(c.color),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(c.icon, color: c.color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(c.label, style: theme.textTheme.bodyLarge)),
                            if (r.segregationResults[c] != null)
                              SegregationChip(result: r.segregationResults[c]!, short: false),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Remarks'),
              AppCard(
                child: Text(
                  r.remarks.isEmpty ? 'No remarks were added.' : r.remarks,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: r.remarks.isEmpty ? AppColors.textMuted : null,
                  ),
                ),
              ),
              if (r.evidenceImageUrls.isNotEmpty) ...[
                const SectionHeader(title: 'Collection evidence'),
                PhotoStrip(urls: r.evidenceImageUrls),
              ],
            ],
          );
        },
      ),
    );
  }
}
