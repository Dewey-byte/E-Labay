import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/schedule_model.dart';
import '../repositories/schedule_repository.dart';

final schedulesProvider = StreamProvider.autoDispose.family<List<Schedule>, ScheduleQuery>(
  (ref, query) => ref.watch(scheduleRepositoryProvider).watchSchedules(query),
);

final scheduleProvider = StreamProvider.autoDispose.family<Schedule?, String>(
  (ref, id) => ref.watch(scheduleRepositoryProvider).watchSchedule(id),
);

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Today's schedules (all statuses), in time order.
final todaySchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final start = _startOfToday();
  return ref.watch(scheduleRepositoryProvider).watchSchedules(
        ScheduleQuery(from: start, to: start.add(const Duration(days: 1)), limit: 50),
      );
});

/// Next pending schedules across campus (Collector dashboard).
final upcomingSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>(
  (ref) => ref.watch(scheduleRepositoryProvider).watchSchedules(
        ScheduleQuery(statuses: ScheduleStatus.pending, from: _startOfToday(), limit: 5),
      ),
);

/// Next pending collection for one office (Faculty dashboard).
final nextOfficeScheduleProvider = StreamProvider.autoDispose.family<Schedule?, String>(
  (ref, officeId) => ref.watch(scheduleRepositoryProvider).watchNextSchedule(officeId),
);

/// Ticks on every schedule write so aggregate counts stay live.
final _scheduleChangesProvider = StreamProvider.autoDispose<String>(
  (ref) => ref.watch(scheduleRepositoryProvider).watchLatestChange(),
);

/// Aggregate schedule counts for the Collector dashboard.
final scheduleCountsProvider = FutureProvider.autoDispose<ScheduleCounts>((ref) async {
  ref.watch(_scheduleChangesProvider);
  return ref.watch(scheduleRepositoryProvider).fetchCounts();
});
