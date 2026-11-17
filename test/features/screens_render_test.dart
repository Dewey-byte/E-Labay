// Renders the main screens with fake provider data at phone sizes to catch
// layout overflows and runtime errors without Firebase.
import 'package:e_labay/core/theme/app_theme.dart';
import 'package:e_labay/core/utils/ranking.dart';
import 'package:e_labay/features/assessment/assessment_screen.dart';
import 'package:e_labay/features/collector/collector_dashboard_screen.dart';
import 'package:e_labay/features/faculty/faculty_dashboard_screen.dart';
import 'package:e_labay/features/leaderboard/leaderboard_screen.dart';
import 'package:e_labay/features/scheduling/schedule_details_screen.dart';
import 'package:e_labay/models/collection_model.dart';
import 'package:e_labay/models/enums.dart';
import 'package:e_labay/models/office_model.dart';
import 'package:e_labay/models/point_transaction_model.dart';
import 'package:e_labay/models/schedule_model.dart';
import 'package:e_labay/models/scoring_config.dart';
import 'package:e_labay/models/user_model.dart';
import 'package:e_labay/providers/auth_provider.dart';
import 'package:e_labay/providers/collection_provider.dart';
import 'package:e_labay/providers/leaderboard_provider.dart';
import 'package:e_labay/providers/office_provider.dart';
import 'package:e_labay/providers/points_provider.dart';
import 'package:e_labay/providers/schedule_provider.dart';
import 'package:e_labay/repositories/schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const collector = AppUser(uid: 'c1', fullName: 'Maria Santos', email: 'c@x.edu', role: UserRole.collector);
const faculty = AppUser(
  uid: 'f1',
  fullName: 'College of Engineering',
  email: 'eng@x.edu',
  role: UserRole.faculty,
  officeId: 'o1',
);

final offices = [
  const Office(
    officeId: 'o1',
    officeName: 'College of Engineering',
    building: 'Engineering Building',
    totalPoints: 170,
    totalCollections: 7,
    totalProperSegregations: 17,
    totalAssessments: 21,
    categoryStats: {
      WasteCategory.biodegradable: CategoryStat(proper: 6, improper: 1),
      WasteCategory.recyclable: CategoryStat(proper: 4, improper: 2),
    },
  ),
  const Office(officeId: 'o2', officeName: "Registrar's Office", building: 'Administration Building', totalPoints: 180),
  const Office(officeId: 'o3', officeName: 'Accounting Office', building: 'Administration Building', totalPoints: 130),
  const Office(officeId: 'o4', officeName: 'College of Nursing with a Very Long Office Name', building: 'Health Sciences', totalPoints: 130),
];

Schedule schedule(String id, int dayOffset, ScheduleStatus status, {int? points}) => Schedule(
      scheduleId: id,
      officeId: 'o1',
      officeName: 'College of Engineering',
      building: 'Engineering Building',
      collectorId: 'c1',
      collectorName: 'Maria Santos',
      collectionDate: DateTime.now().add(Duration(days: dayOffset, hours: 1)),
      collectionTime: '09:00',
      notes: 'Please place the segregated bins outside the dean\'s office before 9 AM.',
      status: status,
      pointsAwarded: points,
    );

CollectionRecord record(String id, int daysAgo, int points) => CollectionRecord(
      collectionId: id,
      scheduleId: id,
      officeId: 'o1',
      officeName: 'College of Engineering',
      collectorId: 'c1',
      collectorName: 'Maria Santos',
      segregationResults: const {
        WasteCategory.biodegradable: SegregationResult.proper,
        WasteCategory.nonBiodegradable: SegregationResult.improper,
        WasteCategory.recyclable: SegregationResult.proper,
        WasteCategory.residual: SegregationResult.notApplicable,
      },
      pointsAwarded: points,
      maxPoints: 30,
      properCount: 2,
      improperCount: 1,
      applicableCount: 3,
      collectedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    );

final records = [for (var i = 0; i < 8; i++) record('r$i', i, 10 + (i % 3) * 10)];
final upcoming = [schedule('s1', 0, ScheduleStatus.scheduled), schedule('s2', 1, ScheduleStatus.upcoming)];

List<Override> common(AppUser user) => [
      currentUserProvider.overrideWithValue(user),
      officesProvider.overrideWith((ref) => Stream.value(offices)),
      officeProvider.overrideWith((ref, id) => Stream.value(offices.first)),
      myOfficeProvider.overrideWith((ref) => Stream.value(offices.first)),
      leaderboardProvider.overrideWith((ref) => Stream.value(rankOffices(offices))),
      scheduleCountsProvider.overrideWith(
        (ref) async => const ScheduleCounts(total: 42, pending: 7, completed: 33, cancelled: 2, today: 2),
      ),
      todaySchedulesProvider.overrideWith((ref) => Stream.value(upcoming.take(1).toList())),
      upcomingSchedulesProvider.overrideWith((ref) => Stream.value(upcoming)),
      recentCollectionsProvider.overrideWith((ref) => Stream.value(records.take(3).toList())),
      weeklyCollectionsProvider.overrideWith((ref) => Stream.value(records)),
      officeCollectionsProvider.overrideWith((ref, args) => Stream.value(records.take(args.$2).toList())),
      nextOfficeScheduleProvider.overrideWith((ref, id) => Stream.value(upcoming.first)),
      scheduleProvider.overrideWith((ref, id) => Stream.value(upcoming.first)),
      scoringConfigProvider.overrideWith((ref) => Stream.value(ScoringConfig.defaults)),
      pointTransactionsProvider.overrideWith(
        (ref, args) => Stream.value([
          PointTransaction(
            transactionId: 't1',
            officeId: 'o1',
            collectionId: 'r0',
            pointsAwarded: 20,
            collectorId: 'c1',
            assessmentDate: DateTime.now(),
          ),
        ]),
      ),
    ];

Future<void> pumpScreen(WidgetTester tester, Widget screen, AppUser user, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: common(user),
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

void main() {
  const sizes = {'small phone': Size(320, 640), 'large phone': Size(412, 915)};

  for (final entry in sizes.entries) {
    group(entry.key, () {
      testWidgets('Collector dashboard', (tester) async {
        await pumpScreen(tester, const CollectorDashboardScreen(), collector, entry.value);
        expect(find.text('Maria Santos'), findsWidgets);
        expect(find.text('Collection statistics'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Faculty dashboard', (tester) async {
        await pumpScreen(tester, const FacultyDashboardScreen(), faculty, entry.value);
        expect(find.text('Accumulated points'), findsOneWidget);
        expect(find.text('170'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Leaderboard with ties and own office highlighted', (tester) async {
        await pumpScreen(tester, const LeaderboardScreen(), faculty, entry.value);
        expect(find.text('Campus leaderboard'), findsOneWidget);
        expect(find.text('Your office'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('You'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('You'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Assessment form shows live score', (tester) async {
        await pumpScreen(tester, const AssessmentScreen(scheduleId: 's1'), collector, entry.value);
        expect(find.text('0 / 0 pts'), findsOneWidget);
        await tester.tap(find.text('Proper').first);
        await tester.pump();
        expect(find.text('10 / 10 pts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Schedule details (collector actions)', (tester) async {
        await pumpScreen(tester, const ScheduleDetailsScreen(scheduleId: 's1'), collector, entry.value);
        expect(find.text('Start collection & assess'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Schedule details (faculty is view-only)', (tester) async {
        await pumpScreen(tester, const ScheduleDetailsScreen(scheduleId: 's1'), faculty, entry.value);
        expect(find.text('Start collection & assess'), findsNothing);
        expect(find.byType(PopupMenuButton<Object>), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
