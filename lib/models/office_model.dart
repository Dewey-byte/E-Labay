import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// Per-category segregation tally kept on each office by Cloud Functions.
class CategoryStat {
  const CategoryStat({this.proper = 0, this.improper = 0});

  final int proper;
  final int improper;

  int get assessed => proper + improper;
  double? get rate => assessed == 0 ? null : proper / assessed;

  factory CategoryStat.fromMap(Map<String, dynamic> data) => CategoryStat(
        proper: readInt(data['proper']),
        improper: readInt(data['improper']),
      );
}

/// `offices/{officeId}` — a participating faculty office.
///
/// The counters (`totalPoints`, `totalCollections`, ...) are maintained only by
/// Cloud Functions. Office documents double as the public leaderboard source,
/// so they contain no private data.
class Office {
  const Office({
    required this.officeId,
    required this.officeName,
    required this.building,
    this.description = '',
    this.totalPoints = 0,
    this.totalCollections = 0,
    this.totalProperSegregations = 0,
    this.totalAssessments = 0,
    this.categoryStats = const {},
    this.lastCollectionAt,
    this.lastPointsAwarded,
    this.createdAt,
    this.updatedAt,
  });

  final String officeId;
  final String officeName;
  final String building;
  final String description;
  final int totalPoints;
  final int totalCollections;
  final int totalProperSegregations;
  final int totalAssessments;
  final Map<WasteCategory, CategoryStat> categoryStats;
  final DateTime? lastCollectionAt;
  final int? lastPointsAwarded;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Share of assessed (non-N/A) categories that were properly segregated.
  double? get properSegregationRate =>
      totalAssessments == 0 ? null : totalProperSegregations / totalAssessments;

  /// Average points earned per completed collection.
  double? get averageScore =>
      totalCollections == 0 ? null : totalPoints / totalCollections;

  CategoryStat statFor(WasteCategory c) => categoryStats[c] ?? const CategoryStat();

  factory Office.fromMap(String id, Map<String, dynamic> data) {
    final rawStats = readMap(data['categoryStats']);
    final stats = <WasteCategory, CategoryStat>{};
    for (final entry in rawStats.entries) {
      final category = WasteCategory.tryParse(entry.key);
      if (category != null) {
        stats[category] = CategoryStat.fromMap(readMap(entry.value));
      }
    }
    return Office(
      officeId: id,
      officeName: readString(data['officeName'], 'Unnamed office'),
      building: readString(data['building']),
      description: readString(data['description']),
      totalPoints: readInt(data['totalPoints']),
      totalCollections: readInt(data['totalCollections']),
      totalProperSegregations: readInt(data['totalProperSegregations']),
      totalAssessments: readInt(data['totalAssessments']),
      categoryStats: stats,
      lastCollectionAt: readDate(data['lastCollectionAt']),
      lastPointsAwarded:
          data['lastPointsAwarded'] == null ? null : readInt(data['lastPointsAwarded']),
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  factory Office.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Office.fromMap(doc.id, doc.data() ?? const {});
}
