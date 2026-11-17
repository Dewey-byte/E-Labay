import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// `collections/{collectionId}` — the record of a completed collection and its
/// waste segregation assessment. Written only by the
/// `submitCollectionAssessment` Cloud Function; the id equals the schedule id,
/// which makes duplicate submissions impossible.
class CollectionRecord {
  const CollectionRecord({
    required this.collectionId,
    required this.scheduleId,
    required this.officeId,
    required this.officeName,
    required this.collectorId,
    required this.segregationResults,
    required this.pointsAwarded,
    this.collectorName = '',
    this.maxPoints = 0,
    this.properCount = 0,
    this.improperCount = 0,
    this.applicableCount = 0,
    this.remarks = '',
    this.evidenceImageUrls = const [],
    this.scheduledDate,
    this.collectedAt,
    this.createdAt,
  });

  final String collectionId;
  final String scheduleId;
  final String officeId;
  final String officeName;
  final String collectorId;
  final String collectorName;
  final Map<WasteCategory, SegregationResult> segregationResults;
  final int pointsAwarded;
  final int maxPoints;
  final int properCount;
  final int improperCount;
  final int applicableCount;
  final String remarks;
  final List<String> evidenceImageUrls;
  final DateTime? scheduledDate;
  final DateTime? collectedAt;
  final DateTime? createdAt;

  double? get properRate => applicableCount == 0 ? null : properCount / applicableCount;

  DateTime get effectiveDate => collectedAt ?? createdAt ?? DateTime.now();

  factory CollectionRecord.fromMap(String id, Map<String, dynamic> data) {
    final raw = readMap(data['segregationResults']);
    final results = <WasteCategory, SegregationResult>{};
    for (final entry in raw.entries) {
      final category = WasteCategory.tryParse(entry.key);
      final result = SegregationResult.tryParse(entry.value as String?);
      if (category != null && result != null) results[category] = result;
    }
    return CollectionRecord(
      collectionId: id,
      scheduleId: readString(data['scheduleId']),
      officeId: readString(data['officeId']),
      officeName: readString(data['officeName'], 'Unknown office'),
      collectorId: readString(data['collectorId']),
      collectorName: readString(data['collectorName']),
      segregationResults: results,
      pointsAwarded: readInt(data['pointsAwarded']),
      maxPoints: readInt(data['maxPoints']),
      properCount: readInt(data['properCount']),
      improperCount: readInt(data['improperCount']),
      applicableCount: readInt(data['applicableCount']),
      remarks: readString(data['remarks']),
      evidenceImageUrls: readStringList(data['evidenceImageUrls']),
      scheduledDate: readDate(data['scheduledDate']),
      collectedAt: readDate(data['collectedAt']),
      createdAt: readDate(data['createdAt']),
    );
  }

  factory CollectionRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CollectionRecord.fromMap(doc.id, doc.data() ?? const {});
}
