import 'package:e_labay/core/theme/app_theme.dart';
import 'package:e_labay/core/utils/formatters.dart';
import 'package:e_labay/models/collection_model.dart';
import 'package:e_labay/shared/components/charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionRecord record(int daysAgo, int points) => CollectionRecord(
      collectionId: 'c$daysAgo',
      scheduleId: 'c$daysAgo',
      officeId: 'o1',
      officeName: 'Office',
      collectorId: 'c1',
      segregationResults: const {},
      pointsAwarded: points,
      maxPoints: 40,
      collectedAt: DateTime(2026, 11, 19).subtract(Duration(days: daysAgo)),
    );

void main() {
  testWidgets('points trend keeps its first and last date labels inside the chart', (tester) async {
    final records = [for (var i = 6; i >= 0; i--) record(i * 2, 20 + (i % 2) * 10)];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, child: PointsTrendChart(collections: records)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final chart = tester.getRect(find.byType(PointsTrendChart));
    final last = Fmt.monthDay(records.last.effectiveDate);
    final first = Fmt.monthDay(records.first.effectiveDate);
    expect(find.text(last), findsOneWidget);
    expect(tester.getRect(find.text(last)).right, lessThanOrEqualTo(chart.right + 0.5));
    expect(tester.getRect(find.text(first)).left, greaterThanOrEqualTo(chart.left - 0.5));
    expect(tester.takeException(), isNull);
  });
}
