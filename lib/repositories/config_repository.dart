import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/scoring_config.dart';

/// Scoring rules stored at `config/scoring`.
class ConfigRepository {
  ConfigRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _scoringDoc => _db
      .collection(FirestoreCollections.config)
      .doc(FirestoreCollections.scoringConfigDoc);

  Stream<ScoringConfig> watchScoringConfig() =>
      _scoringDoc.snapshots().map((doc) => ScoringConfig.fromMap(doc.data()));

  /// Only Collectors may change the scoring rules (validated by rules). New
  /// values apply to future assessments; past awards are never recalculated.
  Future<void> updateScoringConfig(ScoringConfig config, {required String uid}) async {
    try {
      await _scoringDoc.set({
        ...config.toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(ref.watch(firestoreProvider)),
);
