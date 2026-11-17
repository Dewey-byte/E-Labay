import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// `config/scoring` — configurable point values. The Cloud Function reads the
/// same document and is the only authority that actually awards points; the
/// app uses it to preview the score before submission.
class ScoringConfig {
  const ScoringConfig({this.properPoints = 10, this.improperPoints = 0});

  static const defaults = ScoringConfig();
  static const minPoints = 0;
  static const maxPointsPerCategory = 100;

  final int properPoints;
  final int improperPoints;

  int get maxPointsPerCollection => properPoints * WasteCategory.values.length;

  factory ScoringConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return ScoringConfig(
      properPoints: readInt(data['properPoints'], defaults.properPoints)
          .clamp(minPoints, maxPointsPerCategory),
      improperPoints: readInt(data['improperPoints'], defaults.improperPoints)
          .clamp(minPoints, maxPointsPerCategory),
    );
  }

  Map<String, dynamic> toMap() => {
        'properPoints': properPoints,
        'improperPoints': improperPoints,
      };
}
