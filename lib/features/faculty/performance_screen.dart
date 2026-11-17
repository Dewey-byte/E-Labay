import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/office_provider.dart';
import '../../shared/components/office_performance.dart';
import '../../shared/widgets/state_views.dart';

/// Faculty Office: performance overview with statistics and trends.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final office = ref.watch(myOfficeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Office performance')),
      body: AsyncValueView(
        value: office,
        onRetry: () => ref.invalidate(myOfficeProvider),
        data: (o) => o == null
            ? const EmptyState(icon: Icons.apartment, title: 'Office not found')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [OfficePerformanceSection(office: o)],
              ),
      ),
    );
  }
}
