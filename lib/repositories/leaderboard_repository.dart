import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/services/firebase_providers.dart';
import '../core/utils/ranking.dart';
import '../models/office_model.dart';

/// Campus-wide leaderboard built from the public office totals. Totals only
/// change through verified assessments, so they always match the ledger.
class LeaderboardRepository {
  LeaderboardRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<RankedOffice>> watchLeaderboard() => _db
      .collection(FirestoreCollections.offices)
      .orderBy('totalPoints', descending: true)
      .orderBy('officeName')
      .snapshots()
      .map((s) => rankOffices(s.docs.map(Office.fromDoc)));
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>(
  (ref) => LeaderboardRepository(ref.watch(firestoreProvider)),
);
