import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../core/utils/formatters.dart';
import '../core/utils/scoring.dart';
import '../models/collection_model.dart';
import '../models/enums.dart';
import '../models/office_model.dart';
import '../models/schedule_model.dart';
import '../models/scoring_config.dart';
import '../models/user_model.dart';
import 'notification_repository.dart';

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
  CollectionRepository(this._db, this._storage, this._notices);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final NotificationRepository _notices;

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
  /// returns their download URLs. Needs Cloud Storage (Blaze plan).
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

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

  /// Submits an assessment as ONE Firestore transaction that:
  ///  1. creates `collections/{scheduleId}` (id = schedule id),
  ///  2. creates `point_transactions/collection_{scheduleId}`,
  ///  3. adds the points and segregation counts to the office totals,
  ///  4. marks the schedule completed,
  ///  5. notifies the office (completed + points awarded).
  /// Security rules recompute the score from the results and
  /// `config/scoring` and verify every figure, so the write is rejected if
  /// anything is inconsistent, tampered with or already assessed.
  Future<SubmitAssessmentResult> submitAssessment({
    required String scheduleId,
    required AppUser collector,
    required Map<WasteCategory, SegregationResult> results,
    required String remarks,
    required List<String> evidenceImageUrls,
  }) async {
    if (results.length != WasteCategory.values.length) {
      throw const AppException('Assess all waste categories first.');
    }
    final scheduleRef = _db.collection(FirestoreCollections.schedules).doc(scheduleId);
    final collectionRef = _collections.doc(scheduleId);
    final txRef = _db.collection(FirestoreCollections.pointTransactions).doc('collection_$scheduleId');
    final configRef = _db.collection(FirestoreCollections.config).doc(FirestoreCollections.scoringConfigDoc);
    final cleanRemarks = _clip(remarks.trim(), 500);
    final collectorName = _clip(collector.displayName, 120);

    try {
      // Recipients are looked up first (queries cannot run inside a
      // client transaction).
      final initial = await scheduleRef.get();
      if (!initial.exists) throw const AppException('Schedule not found.');
      final recipients = await _notices.officeRecipients(initial.data()!['officeId'] as String);

      return await _db.runTransaction<SubmitAssessmentResult>((tx) async {
        final scheduleSnap = await tx.get(scheduleRef);
        final collectionSnap = await tx.get(collectionRef);
        final configSnap = await tx.get(configRef);
        if (!scheduleSnap.exists) throw const AppException('Schedule not found.');
        final schedule = Schedule.fromDoc(scheduleSnap);
        if (collectionSnap.exists || schedule.status == ScheduleStatus.completed) {
          throw const AppException('This collection has already been assessed.');
        }
        if (schedule.status == ScheduleStatus.cancelled) {
          throw const AppException('This collection was cancelled.');
        }
        final officeRef = _db.collection(FirestoreCollections.offices).doc(schedule.officeId);
        final officeSnap = await tx.get(officeRef);
        if (!officeSnap.exists) throw const AppException('The office for this schedule no longer exists.');
        final office = Office.fromDoc(officeSnap);

        final config = configSnap.exists ? ScoringConfig.fromMap(configSnap.data()) : ScoringConfig.defaults;
        if (!configSnap.exists) {
          tx.set(configRef, {
            ...config.toMap(),
            'updatedBy': collector.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        final score = calculateScore(results, config);
        final now = FieldValue.serverTimestamp();
        final resultMap = {for (final e in results.entries) e.key.key: e.value.value};
        final officeName = _clip(office.officeName, 80);

        tx.set(collectionRef, {
          'collectionId': scheduleId,
          'scheduleId': scheduleId,
          'officeId': schedule.officeId,
          'officeName': officeName,
          'collectorId': collector.uid,
          'collectorName': collectorName,
          'segregationResults': resultMap,
          'properCount': score.properCount,
          'improperCount': score.improperCount,
          'applicableCount': score.applicableCount,
          'pointsAwarded': score.points,
          'maxPoints': score.maxPoints,
          'scoring': config.toMap(),
          'remarks': cleanRemarks,
          'evidenceImageUrls': evidenceImageUrls.take(AppConstants.maxEvidencePhotos).toList(),
          'scheduledDate': scheduleSnap.data()!['collectionDate'],
          'collectedAt': now,
          'createdAt': now,
        });

        tx.set(txRef, {
          'transactionId': txRef.id,
          'officeId': schedule.officeId,
          'officeName': officeName,
          'collectionId': scheduleId,
          'scheduleId': scheduleId,
          'pointsAwarded': score.points,
          'transactionType': 'collection_assessment',
          'properCount': score.properCount,
          'applicableCount': score.applicableCount,
          'remarks': cleanRemarks,
          'collectorId': collector.uid,
          'collectorName': collectorName,
          'assessmentDate': now,
          'createdAt': now,
        });

        tx.update(officeRef, {
          'totalPoints': office.totalPoints + score.points,
          'totalCollections': office.totalCollections + 1,
          'totalProperSegregations': office.totalProperSegregations + score.properCount,
          'totalAssessments': office.totalAssessments + score.applicableCount,
          'categoryStats': {
            for (final c in WasteCategory.values)
              c.key: {
                'proper': office.statFor(c).proper + (results[c] == SegregationResult.proper ? 1 : 0),
                'improper': office.statFor(c).improper + (results[c] == SegregationResult.improper ? 1 : 0),
              },
          },
          'lastCollectionId': scheduleId,
          'lastPointsAwarded': score.points,
          'lastCollectionAt': now,
          'updatedAt': now,
        });

        tx.update(scheduleRef, {
          'status': ScheduleStatus.completed.value,
          'collectionId': scheduleId,
          'pointsAwarded': score.points,
          'completedAt': now,
          'updatedAt': now,
        });

        final summary = '${score.properCount} of ${score.applicableCount} assessed categories were properly segregated';
        _notices.addNotices(
          tx.set,
          recipients: recipients,
          officeId: schedule.officeId,
          notice: OfficeNotice(
            key: 'completed_$scheduleId',
            type: NotificationType.collectionCompleted,
            title: 'Garbage collection completed',
            message: 'Your collection scheduled for ${Fmt.date(schedule.collectionDate)} at '
                '${Fmt.time(schedule.collectionDate)} is complete. Assessment result: $summary.'
                '${cleanRemarks.isEmpty ? '' : ' Collector\'s remarks: "$cleanRemarks"'}',
            scheduleId: scheduleId,
          ),
        );
        _notices.addNotices(
          tx.set,
          recipients: recipients,
          officeId: schedule.officeId,
          notice: OfficeNotice(
            key: 'points_$scheduleId',
            type: NotificationType.pointsAwarded,
            title: score.points > 0 ? 'You earned ${score.points} points!' : 'No points this collection',
            message: score.points > 0
                ? '$officeName earned ${score.points} of ${score.maxPoints} possible points for waste segregation.'
                : '$officeName earned no points this time. Check the assessment to see how to improve.',
            scheduleId: scheduleId,
          ),
        );

        return SubmitAssessmentResult(
          collectionId: scheduleId,
          pointsAwarded: score.points,
          maxPoints: score.maxPoints,
        );
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const AppException(
          'The assessment was rejected. It may already have been submitted, or the scoring rules changed — '
          'reopen the collection and try again.',
          code: 'permission-denied',
        );
      }
      throw AppException.from(e);
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => CollectionRepository(
    ref.watch(firestoreProvider),
    ref.watch(storageProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);
