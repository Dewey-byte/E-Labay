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

enum ScheduleView {
  upcoming('Upcoming'),
  byDate('By date'),
  past('Past');

  const ScheduleView(this.label);
  final String label;
}

/// Builds the query for a schedule view + filters.
ScheduleQuery buildScheduleQuery({
  required ScheduleView view,
  DateTime? date,
  String? officeId,
  ScheduleStatus? status,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final statuses = status == null ? null : [status];
  switch (view) {
    case ScheduleView.upcoming:
      return ScheduleQuery(officeId: officeId, statuses: statuses, from: today);
    case ScheduleView.past:
      return ScheduleQuery(officeId: officeId, statuses: statuses, to: today, descending: true);
    case ScheduleView.byDate:
      final day = Fmt.startOfDay(date ?? now);
      return ScheduleQuery(
        officeId: officeId,
        statuses: statuses,
        from: day,
        to: day.add(const Duration(days: 1)),
      );
  }
}

/// Collector: all collection schedules with view, date, office and status
/// filters.
class ScheduleListScreen extends ConsumerStatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  ConsumerState<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends ConsumerState<ScheduleListScreen> {
  ScheduleView _view = ScheduleView.upcoming;
  DateTime _date = DateTime.now();
  Office? _office;
  ScheduleStatus? _status;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickOffice() async {
    final office = await showOfficePicker(context, selectedId: _office?.officeId);
    if (office != null) setState(() => _office = office);
  }

  @override
  Widget build(BuildContext context) {
    final query = buildScheduleQuery(
      view: _view,
      date: _date,
      officeId: _office?.officeId,
      status: _status,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Collection schedules')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'schedules-new',
        onPressed: () => context.push(AppRoutes.collectorNewSchedule),
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ScheduleView>(
                showSelectedIcon: false,
                segments: [
                  for (final v in ScheduleView.values) ButtonSegment(value: v, label: Text(v.label)),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
          ),
          ScheduleFilterBar(
            date: _view == ScheduleView.byDate ? _date : null,
            onPickDate: _view == ScheduleView.byDate ? _pickDate : null,
            office: _office,
            onPickOffice: _pickOffice,
            onClearOffice: () => setState(() => _office = null),
            status: _status,
            onStatusChanged: (s) => setState(() => _status = s),
          ),
          Expanded(
            child: PagedList(
              key: ValueKey(query),
              watch: (ref, limit) => ref.watch(schedulesProvider(query.copyWith(limit: limit))),
              onRetry: () => ref.invalidate(schedulesProvider),
              itemBuilder: (context, s) => ScheduleTile(
                schedule: s,
                onTap: () => context.push(AppRoutes.collectorSchedule(s.scheduleId)),
              ),
              empty: EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No schedules found',
                message: _view == ScheduleView.upcoming
                    ? 'Create a schedule for a faculty office.'
                    : 'Try another date or filter.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal chips for date / office / status filters.
class ScheduleFilterBar extends StatelessWidget {
  const ScheduleFilterBar({
    super.key,
    this.date,
    this.onPickDate,
    this.office,
    this.onPickOffice,
    this.onClearOffice,
    this.status,
    required this.onStatusChanged,
    this.statusOptions = ScheduleStatus.values,
    this.dateRangeLabel,
    this.onPickDateRange,
    this.onClearDateRange,
  });

  final DateTime? date;
  final VoidCallback? onPickDate;
  final Office? office;
  final VoidCallback? onPickOffice;
  final VoidCallback? onClearOffice;
  final ScheduleStatus? status;
  final ValueChanged<ScheduleStatus?> onStatusChanged;
  final List<ScheduleStatus> statusOptions;
  final String? dateRangeLabel;
  final VoidCallback? onPickDateRange;
  final VoidCallback? onClearDateRange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (onPickDate != null && date != null) ...[
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Text(Fmt.dayLabel(date!)),
              onPressed: onPickDate,
            ),
            const SizedBox(width: 8),
          ],
          if (onPickDateRange != null) ...[
            InputChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: Text(dateRangeLabel ?? 'Any date'),
              selected: dateRangeLabel != null,
              onPressed: onPickDateRange,
              onDeleted: dateRangeLabel != null ? onClearDateRange : null,
            ),
            const SizedBox(width: 8),
          ],
          if (onPickOffice != null) ...[
            InputChip(
              avatar: const Icon(Icons.apartment, size: 16),
              label: Text(office?.officeName ?? 'All offices'),
              selected: office != null,
              onPressed: onPickOffice,
              onDeleted: office != null ? onClearOffice : null,
            ),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<ScheduleStatus?>(
            onSelected: onStatusChanged,
            itemBuilder: (_) => [
              const PopupMenuItem<ScheduleStatus?>(value: null, child: Text('All statuses')),
              for (final s in statusOptions)
                PopupMenuItem<ScheduleStatus?>(
                  value: s,
                  child: Row(
                    children: [
                      Icon(s.icon, size: 18, color: s.color),
                      const SizedBox(width: 10),
                      Text(s.label),
                    ],
                  ),
                ),
            ],
            child: Chip(
              avatar: Icon(status?.icon ?? Icons.filter_list, size: 16, color: status?.color),
              label: Text(status?.label ?? 'All statuses'),
              backgroundColor: status == null ? null : Theme.of(context).chipTheme.selectedColor,
            ),
          ),
        ],
      ),
    );
  }
}
