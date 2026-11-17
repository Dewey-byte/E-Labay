// End-to-end test of the Spark-plan design: the app's real repositories
// against the Firebase emulators and the real firestore.rules.
//
//   npm run emulators            (terminal 1)
//   npm run seed -- --minimal    (terminal 2: creates the demo Collector)
//   flutter test integration_test -d <android-emulator-id> --dart-define=USE_FIREBASE_EMULATORS=true
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_labay/core/exceptions/app_exception.dart';
import 'package:e_labay/core/services/emulator_config.dart';
import 'package:e_labay/models/enums.dart';
import 'package:e_labay/models/office_model.dart';
import 'package:e_labay/models/schedule_model.dart';
import 'package:e_labay/models/user_model.dart';
import 'package:e_labay/repositories/collection_repository.dart';
import 'package:e_labay/repositories/notification_repository.dart';
import 'package:e_labay/repositories/office_repository.dart';
import 'package:e_labay/repositories/schedule_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseFirestore db;
  late FirebaseAuth auth;
  late NotificationRepository notices;
  late OfficeRepository offices;
  late ScheduleRepository schedules;
  late CollectionRepository collections;

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final facultyEmail = 'it$stamp@elabay.test';
  const facultyPassword = 'office123';
  late String officeId;
  late String facultyUid;
  late String scheduleId;

  Future<AppUser> signInCollector() async {
    await auth.signOut();
    final cred = await auth.signInWithEmailAndPassword(email: 'collector@elabay.test', password: 'collector123');
    return AppUser.fromDoc(await db.collection('users').doc(cred.user!.uid).get());
  }

  Future<Schedule> schedule(String id) async => Schedule.fromDoc(await db.collection('schedules').doc(id).get());
  Future<Office> office() async => Office.fromDoc(await db.collection('offices').doc(officeId).get());

  setUpAll(() async {
    assert(EmulatorConfig.enabled, 'Run with --dart-define=USE_FIREBASE_EMULATORS=true');
    await Firebase.initializeApp(options: EmulatorConfig.options);
    await EmulatorConfig.connect();
    db = FirebaseFirestore.instance;
    auth = FirebaseAuth.instance;
    notices = NotificationRepository(db);
    offices = OfficeRepository(db, auth);
    schedules = ScheduleRepository(db, notices);
    collections = CollectionRepository(db, FirebaseStorage.instance, notices);
  });

  testWidgets('Collector provisions an office account without losing the session', (tester) async {
    final collector = await signInCollector();
    final result = await offices.provisionFacultyAccount(
      officeName: 'Integration Office $stamp',
      building: 'Test Building',
      description: '',
      fullName: 'Integration Office',
      email: facultyEmail,
      password: facultyPassword,
    );
    officeId = result.officeId;
    facultyUid = result.uid;
    expect(auth.currentUser!.uid, collector.uid, reason: 'Collector stays signed in');
    final profile = AppUser.fromDoc(await db.collection('users').doc(facultyUid).get());
    expect(profile.role, UserRole.faculty);
    expect(profile.officeId, officeId);
    expect((await office()).totalPoints, 0);

    await expectLater(
      offices.provisionFacultyAccount(
        officeId: officeId, fullName: 'Dup', email: facultyEmail, password: facultyPassword),
      throwsA(isA<AppException>()),
    );
  });

  testWidgets('Collector schedules, starts and assesses a collection', (tester) async {
    final collector = await signInCollector();
    scheduleId = await schedules.createSchedule(
      office: await office(),
      collector: collector,
      collectionDate: DateTime.now().add(const Duration(hours: 2)),
      collectionTime: '09:00',
      notes: 'Bins by the door',
    );
    await schedules.markInProgress(scheduleId);
    final result = await collections.submitAssessment(
      scheduleId: scheduleId,
      collector: collector,
      results: const {
        WasteCategory.biodegradable: SegregationResult.proper,
        WasteCategory.nonBiodegradable: SegregationResult.proper,
        WasteCategory.recyclable: SegregationResult.improper,
        WasteCategory.residual: SegregationResult.notApplicable,
      },
      remarks: 'Recyclables mixed with food waste',
      evidenceImageUrls: const [],
    );
    expect(result.pointsAwarded, 20);
    expect(result.maxPoints, 30);

    final o = await office();
    expect(o.totalPoints, 20);
    expect(o.totalCollections, 1);
    expect(o.totalProperSegregations, 2);
    expect(o.totalAssessments, 3);
    expect(o.statFor(WasteCategory.recyclable).improper, 1);
    final s = await schedule(scheduleId);
    expect(s.status, ScheduleStatus.completed);
    expect(s.pointsAwarded, 20);
    final tx = await db.collection('point_transactions').doc('collection_$scheduleId').get();
    expect(tx.data()!['pointsAwarded'], 20);
  });

  testWidgets('Duplicate submissions are rejected and never double-award', (tester) async {
    final collector = await signInCollector();
    await expectLater(
      collections.submitAssessment(
        scheduleId: scheduleId,
        collector: collector,
        results: {for (final c in WasteCategory.values) c: SegregationResult.proper},
        remarks: '',
        evidenceImageUrls: const [],
      ),
      throwsA(isA<AppException>()),
    );
    expect((await office()).totalPoints, 20);
  });

  testWidgets('Reschedule, cancel and reminders notify the office', (tester) async {
    final collector = await signInCollector();
    final soon = await schedules.createSchedule(
      office: await office(),
      collector: collector,
      collectionDate: DateTime.now().add(const Duration(hours: 3)),
      collectionTime: '10:00',
      notes: '',
    );
    expect(await schedules.sendDueReminders(), greaterThanOrEqualTo(1));
    expect((await schedule(soon)).status, ScheduleStatus.upcoming);

    final later = await schedules.createSchedule(
      office: await office(),
      collector: collector,
      collectionDate: DateTime.now().add(const Duration(days: 3)),
      collectionTime: '08:00',
      notes: '',
    );
    final original = await schedule(later);
    await schedules.reschedule(
      original,
      collectionDate: original.collectionDate.add(const Duration(days: 1)),
      collectionTime: '08:00',
      reason: 'Campus event',
    );
    expect((await schedule(later)).status, ScheduleStatus.rescheduled);
    await schedules.cancel(await schedule(later), reason: 'Holiday');
    expect((await schedule(later)).status, ScheduleStatus.cancelled);
  });

  testWidgets('Faculty sees its own records and notifications but cannot manage schedules', (tester) async {
    await auth.signOut();
    await auth.signInWithEmailAndPassword(email: facultyEmail, password: facultyPassword);
    final own = await db.collection('collections').doc(scheduleId).get();
    expect(own.data()!['pointsAwarded'], 20);

    // Read from the server: the first snapshot of a listener may come from
    // the device's local cache, which never contains transaction writes.
    final feedSnap = await db
        .collection('notifications')
        .where('recipientId', isEqualTo: facultyUid)
        .get(const GetOptions(source: Source.server));
    final types = feedSnap.docs.map((d) => NotificationType.parse(d.data()['notificationType'] as String?)).toSet();
    expect(types, containsAll(<NotificationType>[
      NotificationType.scheduleCreated,
      NotificationType.collectionCompleted,
      NotificationType.pointsAwarded,
      NotificationType.scheduleReminder,
      NotificationType.scheduleRescheduled,
      NotificationType.scheduleCancelled,
    ]));
    await notices.markAsRead(feedSnap.docs.first.id);

    await expectLater(
      db.collection('schedules').doc('forged').set({'officeId': officeId, 'status': 'scheduled'}),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      db.collection('offices').doc(officeId).update({'totalPoints': 9999}),
      throwsA(isA<FirebaseException>()),
    );
  });

  testWidgets('Deactivated accounts lose access', (tester) async {
    await signInCollector();
    await offices.setAccountStatus(uid: facultyUid, isActive: false);
    await auth.signOut();
    await auth.signInWithEmailAndPassword(email: facultyEmail, password: facultyPassword);
    await expectLater(
      db.collection('schedules').doc(scheduleId).get(),
      throwsA(isA<FirebaseException>()),
    );
    await auth.signOut();
  });
}
