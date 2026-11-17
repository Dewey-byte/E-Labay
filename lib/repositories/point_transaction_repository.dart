import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/services/firebase_providers.dart';
import '../models/point_transaction_model.dart';

/// Read-only access to the point transaction ledger (written by Cloud
/// Functions only).
class PointTransactionRepository {
  PointTransactionRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<PointTransaction>> watchTransactions(
    String officeId, {
    int limit = AppConstants.pageSize,
  }) =>
      _db
          .collection(FirestoreCollections.pointTransactions)
          .where('officeId', isEqualTo: officeId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(PointTransaction.fromDoc).toList());
}

final pointTransactionRepositoryProvider = Provider<PointTransactionRepository>(
  (ref) => PointTransactionRepository(ref.watch(firestoreProvider)),
);
