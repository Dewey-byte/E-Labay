import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../routes/app_routes.dart';
import '../../shared/components/schedule_tile.dart';
import '../../shared/widgets/paged_list.dart';
import '../../shared/widgets/state_views.dart';
import '../scheduling/schedule_list_screen.dart';

/// Faculty Office: own collection schedules (view only).
class FacultyScheduleScreen extends ConsumerStatefulWidget {
  const FacultyScheduleScreen({super.key});

  @override
  ConsumerState<FacultyScheduleScreen> createState() => _FacultyScheduleScreenState();
}

class _FacultyScheduleScreenState extends ConsumerState<FacultyScheduleScreen> {
  ScheduleView _view = ScheduleView.upcoming;
  ScheduleStatus? _status;

  @override
  Widget build(BuildContext context) {
    final officeId = ref.watch(currentUserProvider)?.officeId;
    if (officeId == null) return const Scaffold(body: LoadingView());
    final query = buildScheduleQuery(
      view: _view == ScheduleView.byDate ? ScheduleView.upcoming : _view,
      officeId: officeId,
      status: _status,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Collection schedule')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ScheduleView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ScheduleView.upcoming, label: Text('Upcoming')),
                  ButtonSegment(value: ScheduleView.past, label: Text('Past')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
          ),
          ScheduleFilterBar(status: _status, onStatusChanged: (s) => setState(() => _status = s)),
          Expanded(
            child: PagedList(
              key: ValueKey(query),
              watch: (ref, limit) => ref.watch(schedulesProvider(query.copyWith(limit: limit))),
              onRetry: () => ref.invalidate(schedulesProvider),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemBuilder: (context, s) => ScheduleTile(
                schedule: s,
                showOffice: false,
                onTap: () => context.push(AppRoutes.facultySchedule(s.scheduleId)),
              ),
              empty: EmptyState(
                icon: Icons.event_available_outlined,
                title: _view == ScheduleView.upcoming ? 'No upcoming collections' : 'No past collections',
                message: _view == ScheduleView.upcoming
                    ? 'The Collector will notify you when a collection is scheduled.'
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
