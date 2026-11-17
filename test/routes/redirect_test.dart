import 'package:e_labay/models/enums.dart';
import 'package:e_labay/models/user_model.dart';
import 'package:e_labay/providers/auth_provider.dart';
import 'package:e_labay/routes/app_router.dart';
import 'package:e_labay/routes/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

const collector = AppUser(uid: 'c', fullName: 'C', email: 'c@x.edu', role: UserRole.collector);
const faculty = AppUser(
  uid: 'f',
  fullName: 'F',
  email: 'f@x.edu',
  role: UserRole.faculty,
  officeId: 'office1',
);

void main() {
  group('role-based redirect', () {
    test('loading waits on splash but keeps the login screen', () {
      expect(resolveRedirect(const SessionLoading(), AppRoutes.collectorDashboard), AppRoutes.splash);
      expect(resolveRedirect(const SessionLoading(), AppRoutes.splash), isNull);
      expect(resolveRedirect(const SessionLoading(), AppRoutes.login), isNull);
    });

    test('signed-out and invalid sessions go to login', () {
      expect(resolveRedirect(const SessionSignedOut(), AppRoutes.facultyDashboard), AppRoutes.login);
      expect(resolveRedirect(const SessionInvalid('x'), '/collector/schedules'), AppRoutes.login);
      expect(resolveRedirect(const SessionSignedOut(), AppRoutes.login), isNull);
    });

    test('collector lands on the collector dashboard and cannot open faculty routes', () {
      const s = SessionReady(collector);
      expect(resolveRedirect(s, AppRoutes.login), AppRoutes.collectorDashboard);
      expect(resolveRedirect(s, AppRoutes.splash), AppRoutes.collectorDashboard);
      expect(resolveRedirect(s, AppRoutes.facultyLeaderboard), AppRoutes.collectorDashboard);
      expect(resolveRedirect(s, AppRoutes.collectorSchedule('abc')), isNull);
    });

    test('faculty lands on the faculty dashboard and cannot open collector routes', () {
      const s = SessionReady(faculty);
      expect(resolveRedirect(s, AppRoutes.login), AppRoutes.facultyDashboard);
      expect(resolveRedirect(s, AppRoutes.collectorNewSchedule), AppRoutes.facultyDashboard);
      expect(resolveRedirect(s, AppRoutes.collectorAssess('abc')), AppRoutes.facultyDashboard);
      expect(resolveRedirect(s, AppRoutes.facultyNotifications), isNull);
    });
  });
}
