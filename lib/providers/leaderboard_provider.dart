import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/ranking.dart';
import '../repositories/leaderboard_repository.dart';
import 'auth_provider.dart';

/// Live campus leaderboard — re-ranks whenever any office's points change.
final leaderboardProvider = StreamProvider.autoDispose<List<RankedOffice>>(
  (ref) => ref.watch(leaderboardRepositoryProvider).watchLeaderboard(),
);

/// The signed-in office's leaderboard entry (null for Collectors or while
/// loading).
final myRankProvider = Provider.autoDispose<RankedOffice?>((ref) {
  final officeId = ref.watch(currentUserProvider)?.officeId;
  final board = ref.watch(leaderboardProvider).value;
  if (officeId == null || board == null) return null;
  for (final entry in board) {
    if (entry.office.officeId == officeId) return entry;
  }
  return null;
});
