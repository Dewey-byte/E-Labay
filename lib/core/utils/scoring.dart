import '../../models/enums.dart';
import '../../models/scoring_config.dart';

/// Result of scoring one assessment. Mirrors `scoreAssessment` in
/// `functions/src/scoring.ts`, which is the authoritative implementation.
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.points,
    required this.maxPoints,
    required this.properCount,
    required this.improperCount,
    required this.applicableCount,
  });

  final int points;
  final int maxPoints;
  final int properCount;
  final int improperCount;
  final int applicableCount;

  double? get properRate => applicableCount == 0 ? null : properCount / applicableCount;
}

/// Scores an assessment:
/// * properly segregated category -> `config.properPoints`
/// * improperly segregated category -> `config.improperPoints`
/// * not applicable -> excluded (counts toward neither points nor maximum)
ScoreBreakdown calculateScore(
  Map<WasteCategory, SegregationResult> results,
  ScoringConfig config,
) {
  var proper = 0;
  var improper = 0;
  for (final category in WasteCategory.values) {
    switch (results[category]) {
      case SegregationResult.proper:
        proper++;
      case SegregationResult.improper:
        improper++;
      case SegregationResult.notApplicable:
      case null:
        break;
    }
  }
  final applicable = proper + improper;
  return ScoreBreakdown(
    points: proper * config.properPoints + improper * config.improperPoints,
    maxPoints: applicable * config.properPoints,
    properCount: proper,
    improperCount: improper,
    applicableCount: applicable,
  );
}
