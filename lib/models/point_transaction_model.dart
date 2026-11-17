import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';

/// `point_transactions/{transactionId}` — permanent, append-only ledger of
/// points awarded to an office. The id is derived from the collection id so a
/// collection can never be credited twice.
class PointTransaction {
  const PointTransaction({
    required this.transactionId,
    required this.officeId,
    required this.collectionId,
    required this.pointsAwarded,
    required this.collectorId,
    this.officeName = '',
    this.scheduleId = '',
    this.transactionType = 'collection_assessment',
    this.remarks = '',
    this.collectorName = '',
    this.properCount = 0,
    this.applicableCount = 0,
    this.assessmentDate,
    this.createdAt,
  });

  final String transactionId;
  final String officeId;
  final String officeName;
  final String collectionId;
  final String scheduleId;
  final int pointsAwarded;
  final String transactionType;
  final String remarks;
  final String collectorId;
  final String collectorName;
  final int properCount;
  final int applicableCount;
  final DateTime? assessmentDate;
  final DateTime? createdAt;

  DateTime get effectiveDate => assessmentDate ?? createdAt ?? DateTime.now();

  factory PointTransaction.fromMap(String id, Map<String, dynamic> data) =>
      PointTransaction(
        transactionId: id,
        officeId: readString(data['officeId']),
        officeName: readString(data['officeName']),
        collectionId: readString(data['collectionId']),
        scheduleId: readString(data['scheduleId']),
        pointsAwarded: readInt(data['pointsAwarded']),
        transactionType: readString(data['transactionType'], 'collection_assessment'),
        remarks: readString(data['remarks']),
        collectorId: readString(data['collectorId']),
        collectorName: readString(data['collectorName']),
        properCount: readInt(data['properCount']),
        applicableCount: readInt(data['applicableCount']),
        assessmentDate: readDate(data['assessmentDate']),
        createdAt: readDate(data['createdAt']),
      );

  factory PointTransaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      PointTransaction.fromMap(doc.id, doc.data() ?? const {});
}
