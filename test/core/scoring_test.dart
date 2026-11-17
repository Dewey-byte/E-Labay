import 'package:e_labay/core/utils/scoring.dart';
import 'package:e_labay/models/enums.dart';
import 'package:e_labay/models/scoring_config.dart';
import 'package:flutter_test/flutter_test.dart';

Map<WasteCategory, SegregationResult> all(SegregationResult r) =>
    {for (final c in WasteCategory.values) c: r};

void main() {
  group('calculateScore (mirrors functions/src/scoring.ts)', () {
    test('all proper earns the 40-point maximum', () {
      final s = calculateScore(all(SegregationResult.proper), ScoringConfig.defaults);
      expect(s.points, 40);
      expect(s.maxPoints, 40);
      expect(s.properRate, 1);
    });

    test('improper earns 0, not applicable is excluded', () {
      final s = calculateScore({
        WasteCategory.biodegradable: SegregationResult.proper,
        WasteCategory.nonBiodegradable: SegregationResult.improper,
        WasteCategory.recyclable: SegregationResult.notApplicable,
        WasteCategory.residual: SegregationResult.proper,
      }, ScoringConfig.defaults);
      expect(s.points, 20);
      expect(s.maxPoints, 30);
      expect(s.applicableCount, 3);
      expect(s.properRate, closeTo(2 / 3, 1e-9));
    });

    test('all not applicable has no rate', () {
      final s = calculateScore(all(SegregationResult.notApplicable), ScoringConfig.defaults);
      expect(s.points, 0);
      expect(s.maxPoints, 0);
      expect(s.properRate, isNull);
    });

    test('unassessed categories count for nothing', () {
      final s = calculateScore({WasteCategory.recyclable: SegregationResult.proper}, ScoringConfig.defaults);
      expect(s.points, 10);
      expect(s.applicableCount, 1);
    });

    test('uses configured values', () {
      final s = calculateScore(
        all(SegregationResult.improper),
        const ScoringConfig(properPoints: 15, improperPoints: 5),
      );
      expect(s.points, 20);
      expect(s.maxPoints, 60);
    });
  });

  group('ScoringConfig.fromMap', () {
    test('defaults when missing and clamps out-of-range values', () {
      expect(ScoringConfig.fromMap(null).properPoints, 10);
      final c = ScoringConfig.fromMap({'properPoints': 500, 'improperPoints': -2});
      expect(c.properPoints, 100);
      expect(c.improperPoints, 0);
      expect(const ScoringConfig().maxPointsPerCollection, 40);
    });
  });
}
