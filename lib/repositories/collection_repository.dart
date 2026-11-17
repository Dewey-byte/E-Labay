import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/collection_model.dart';
import '../models/enums.dart';

class SubmitAssessmentResult {
  const SubmitAssessmentResult({
    required this.collectionId,
    required this.pointsAwarded,
    required this.maxPoints,
  });

  final String collectionId;
  final int pointsAwarded;
  final int maxPoints;
}

/// Completed collections and their assessments.
class CollectionRepository {
  CollectionRepository(this._db, this._functions, this._storage);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _collections =>
      _db.collection(FirestoreCollections.collections);

  Stream<CollectionRecord?> watchCollection(String collectionId) => _collections
      .doc(collectionId)
      .snapshots()
      .map((doc) => doc.exists ? CollectionRecord.fromDoc(doc) : null);

  /// Most recent collections, optionally for one office.
  Stream<List<CollectionRecord>> watchRecent({String? officeId, int limit = 5}) {
    Query<Map<String, dynamic>> q = _collections;
    if (officeId != null) q = q.where('officeId', isEqualTo: officeId);
    return q
        .orderBy('collectedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(CollectionRecord.fromDoc).toList());
  }

  /// Collections on or after [since] (all offices) — dashboard statistics.
  Stream<List<CollectionRecord>> watchSince(DateTime since) => _collections
      .where('collectedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('collectedAt')
      .snapshots()
      .map((s) => s.docs.map(CollectionRecord.fromDoc).toList());

  /// Uploads evidence photos to `collections/{officeId}/{scheduleId}/` and
  /// returns their download URLs. Storage rules allow Collectors only.
  Future<List<String>> uploadEvidence({
    required String officeId,
    required String scheduleId,
    required List<XFile> photos,
  }) async {
    try {
      final urls = <String>[];
      for (var i = 0; i < photos.length; i++) {
        final name = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final ref = _storage.ref(StoragePaths.evidence(officeId, scheduleId, name));
        final bytes = await photos[i].readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        urls.add(await ref.getDownloadURL());
      }
      return urls;
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Submits the assessment to the `submitCollectionAssessment` Cloud
  /// Function, which validates it, computes points, writes the collection,
  /// the point transaction and the office totals in one transaction, and
  /// notifies the office.
  Future<SubmitAssessmentResult> submitAssessment({
    required String scheduleId,
    required Map<WasteCategory, SegregationResult> results,
    required String remarks,
    required List<String> evidenceImageUrls,
  }) async {
    try {
      final response = await _functions
          .httpsCallable(CloudFunctionNames.submitCollectionAssessment)
          .call<Map<String, dynamic>>({
        'scheduleId': scheduleId,
        'segregationResults': {
          for (final entry in results.entries) entry.key.key: entry.value.value,
        },
        'remarks': remarks.trim(),
        'evidenceImageUrls': evidenceImageUrls,
      });
      final data = Map<String, dynamic>.from(response.data);
      return SubmitAssessmentResult(
        collectionId: data['collectionId'] as String,
        pointsAwarded: (data['pointsAwarded'] as num).toInt(),
        maxPoints: (data['maxPoints'] as num).toInt(),
      );
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => CollectionRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(storageProvider),
  ),
);
