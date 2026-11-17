import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../core/utils/ranking.dart';
import '../models/office_model.dart';

/// Campus-wide leaderboard built from the public office counters.
class LeaderboardRepository {
  LeaderboardRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<List<RankedOffice>> watchLeaderboard() => _db
      .collection(FirestoreCollections.offices)
      .orderBy('totalPoints', descending: true)
      .orderBy('officeName')
      .snapshots()
      .map((s) => rankOffices(s.docs.map(Office.fromDoc)));

  /// Collector maintenance action: recompute every office's totals from the
  /// point transaction ledger (server-side) to guarantee consistency.
  Future<int> recalculate() async {
    try {
      final result = await _functions
          .httpsCallable(CloudFunctionNames.recalculateLeaderboard)
          .call<Map<String, dynamic>>();
      return ((result.data)['officesUpdated'] as num?)?.toInt() ?? 0;
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>(
  (ref) => LeaderboardRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider)),
);
