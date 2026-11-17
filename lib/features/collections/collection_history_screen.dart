import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/office_model.dart';
import '../../providers/schedule_provider.dart';
import '../../repositories/schedule_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/office_picker_sheet.dart';
import '../../shared/components/schedule_tile.dart';
import '../../shared/widgets/paged_list.dart';
import '../../shared/widgets/state_views.dart';
import '../scheduling/schedule_list_screen.dart';

/// Collector: previous collections (completed and cancelled) with office,
/// date-range and status filters. Completed entries open the assessment.
class CollectionHistoryScreen extends ConsumerStatefulWidget {
  const CollectionHistoryScreen({super.key});

  @override
  ConsumerState<CollectionHistoryScreen> createState() => _CollectionHistoryScreenState();
}

class _CollectionHistoryScreenState extends ConsumerState<CollectionHistoryScreen> {
  Office? _office;
  ScheduleStatus? _status;
  DateTimeRange? _range;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDateRange: _range,
      helpText: 'Filter by collection date',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickOffice() async {
    final office = await showOfficePicker(context, selectedId: _office?.officeId);
    if (office != null) setState(() => _office = office);
  }

  @override
  Widget build(BuildContext context) {
    final query = ScheduleQuery(
      officeId: _office?.officeId,
      statuses: _status == null ? ScheduleStatus.history : [_status!],
      from: _range == null ? null : Fmt.startOfDay(_range!.start),
      to: _range == null ? null : Fmt.startOfDay(_range!.end).add(const Duration(days: 1)),
      descending: true,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Collection history')),
      body: Column(
        children: [
          ScheduleFilterBar(
            dateRangeLabel: _range == null
                ? null
                : '${Fmt.monthDay(_range!.start)} – ${Fmt.monthDay(_range!.end)}',
            onPickDateRange: _pickRange,
            onClearDateRange: () => setState(() => _range = null),
            office: _office,
            onPickOffice: _pickOffice,
            onClearOffice: () => setState(() => _office = null),
            status: _status,
            statusOptions: ScheduleStatus.history,
            onStatusChanged: (s) => setState(() => _status = s),
          ),
          Expanded(
            child: PagedList(
              key: ValueKey(query),
              watch: (ref, limit) => ref.watch(schedulesProvider(query.copyWith(limit: limit))),
              onRetry: () => ref.invalidate(schedulesProvider),
              itemBuilder: (context, s) => ScheduleTile(
                schedule: s,
                onTap: () => s.collectionId != null
                    ? context.push(AppRoutes.collectorCollection(s.collectionId!))
                    : context.push(AppRoutes.collectorSchedule(s.scheduleId)),
              ),
              empty: const EmptyState(
                icon: Icons.history,
                title: 'No collections found',
                message: 'Completed and cancelled collections appear here.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
