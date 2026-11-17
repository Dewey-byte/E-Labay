import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_labay/models/collection_model.dart';
import 'package:e_labay/models/enums.dart';
import 'package:e_labay/models/notification_model.dart';
import 'package:e_labay/models/office_model.dart';
import 'package:e_labay/models/schedule_model.dart';
import 'package:e_labay/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppUser parses role and rejects unknown roles', () {
    final u = AppUser.fromMap('u1', {
      'fullName': 'Ana',
      'email': 'ana@x.edu',
      'role': 'faculty',
      'officeId': 'o1',
      'isActive': true,
    });
    expect(u.role, UserRole.faculty);
    expect(u.officeId, 'o1');
    expect(u.pushEnabled, isTrue);
    expect(() => AppUser.fromMap('u2', {'role': 'admin'}), throwsFormatException);
    expect(() => AppUser.fromMap('u3', {}), throwsFormatException);
  });

  test('Office computes rates and category stats', () {
    final o = Office.fromMap('o1', {
      'officeName': 'Registrar',
      'building': 'Admin',
      'totalPoints': 90,
      'totalCollections': 3,
      'totalProperSegregations': 9,
      'totalAssessments': 12,
      'categoryStats': {
        'recyclable': {'proper': 2, 'improper': 1},
        'unknown_category': {'proper': 5},
      },
    });
    expect(o.properSegregationRate, 0.75);
    expect(o.averageScore, 30);
    expect(o.statFor(WasteCategory.recyclable).rate, closeTo(2 / 3, 1e-9));
    expect(o.statFor(WasteCategory.residual).rate, isNull);
    expect(o.categoryStats.length, 1);
  });

  test('Schedule parses status and detects overdue collections', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final s = Schedule.fromMap('s1', {
      'officeId': 'o1',
      'officeName': 'Registrar',
      'collectorId': 'c1',
      'collectionDate': Timestamp.fromDate(yesterday),
      'collectionTime': '09:00',
      'status': 'rescheduled',
    });
    expect(s.status, ScheduleStatus.rescheduled);
    expect(s.isOverdue, isTrue);
    expect(s.canBeAssessed, isTrue);

    final done = Schedule.fromMap('s2', {
      'collectionDate': Timestamp.fromDate(yesterday),
      'status': 'completed',
      'pointsAwarded': 30,
    });
    expect(done.isOverdue, isFalse);
    expect(done.canBeAssessed, isFalse);
    expect(done.pointsAwarded, 30);
    expect(ScheduleStatus.parse('in_progress'), ScheduleStatus.inProgress);
  });

  test('CollectionRecord parses segregation results', () {
    final c = CollectionRecord.fromMap('s1', {
      'officeId': 'o1',
      'collectorId': 'c1',
      'segregationResults': {
        'biodegradable': 'proper',
        'non_biodegradable': 'improper',
        'recyclable': 'not_applicable',
        'residual': 'proper',
      },
      'pointsAwarded': 20,
      'properCount': 2,
      'applicableCount': 3,
      'evidenceImageUrls': ['https://example.com/a.jpg', 42],
    });
    expect(c.segregationResults[WasteCategory.nonBiodegradable], SegregationResult.improper);
    expect(c.segregationResults.length, 4);
    expect(c.properRate, closeTo(2 / 3, 1e-9));
    expect(c.evidenceImageUrls, ['https://example.com/a.jpg']);
  });

  test('AppNotification maps types to their related record', () {
    final n = AppNotification.fromMap('n1', {
      'recipientId': 'u1',
      'title': 'Rescheduled',
      'message': 'Moved',
      'notificationType': 'schedule_rescheduled',
      'relatedId': 's1',
    });
    expect(n.type, NotificationType.scheduleRescheduled);
    expect(n.type.relatesToSchedule, isTrue);
    expect(n.isRead, isFalse);
    expect(NotificationType.parse('points_awarded').relatesToCollection, isTrue);
    expect(NotificationType.parse('something_else'), NotificationType.general);
  });
}
