import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/assessment/assessment_screen.dart';
import '../features/assessment/assessment_submitted_screen.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/splash_screen.dart';
import '../features/collections/collection_details_screen.dart';
import '../features/collections/collection_history_screen.dart';
import '../features/collector/collector_dashboard_screen.dart';
import '../features/collector/collector_shell.dart';
import '../features/collector/faculty_account_form_screen.dart';
import '../features/collector/office_details_screen.dart';
import '../features/collector/office_form_screen.dart';
import '../features/collector/office_list_screen.dart';
import '../features/faculty/faculty_dashboard_screen.dart';
import '../features/faculty/faculty_schedule_screen.dart';
import '../features/faculty/faculty_shell.dart';
import '../features/faculty/performance_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/notifications/notification_details_screen.dart';
import '../features/notifications/notification_feed_screen.dart';
import '../features/points/points_history_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/scheduling/schedule_details_screen.dart';
import '../features/scheduling/schedule_form_screen.dart';
import '../features/scheduling/schedule_list_screen.dart';
import '../models/enums.dart';
import '../providers/auth_provider.dart';
import 'app_routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Computes the redirect for the current session. Pure function so it can be
/// unit-tested.
String? resolveRedirect(SessionState session, String location) {
  final atSplash = location == AppRoutes.splash;
  final atLogin = location == AppRoutes.login;

  switch (session) {
    case SessionLoading():
      // Stay on the login screen while a sign-in completes; otherwise wait on
      // the splash screen.
      return atSplash || atLogin ? null : AppRoutes.splash;
    case SessionSignedOut():
    case SessionInvalid():
      return atLogin ? null : AppRoutes.login;
    case SessionReady(:final user):
      final home = user.role == UserRole.collector
          ? AppRoutes.collectorDashboard
          : AppRoutes.facultyDashboard;
      final area = user.role == UserRole.collector ? '/collector' : '/faculty';
      if (atSplash || atLogin || !location.startsWith(area)) return home;
      return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget Function(GoRouterState s) builder) => GoRoute(
        path: path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => builder(state),
      );

  StatefulShellBranch tab(String path, Widget child) => StatefulShellBranch(
        routes: [GoRoute(path: path, pageBuilder: (_, _) => NoTransitionPage(child: child))],
      );

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(ref.read(sessionProvider), state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),

      // ---------------- Collector ----------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => CollectorShell(navigationShell: shell),
        branches: [
          tab(AppRoutes.collectorDashboard, const CollectorDashboardScreen()),
          tab(AppRoutes.collectorSchedules, const ScheduleListScreen()),
          tab(AppRoutes.collectorOffices, const OfficeListScreen()),
          tab(AppRoutes.collectorHistory, const CollectionHistoryScreen()),
          tab(AppRoutes.collectorProfile, const ProfileScreen()),
        ],
      ),
      page(
        AppRoutes.collectorNewSchedule,
        (s) => ScheduleFormScreen(initialOfficeId: s.uri.queryParameters['officeId']),
      ),
      page('/collector/schedule/:id', (s) => ScheduleDetailsScreen(scheduleId: s.pathParameters['id']!)),
      page('/collector/schedule/:id/edit', (s) => ScheduleFormScreen(scheduleId: s.pathParameters['id'])),
      page('/collector/schedule/:id/assess', (s) => AssessmentScreen(scheduleId: s.pathParameters['id']!)),
      page(
        '/collector/schedule/:id/submitted',
        (s) => AssessmentSubmittedScreen(scheduleId: s.pathParameters['id']!),
      ),
      page(AppRoutes.collectorNewOffice, (_) => const OfficeFormScreen()),
      page('/collector/office/:id', (s) => OfficeDetailsScreen(officeId: s.pathParameters['id']!)),
      page('/collector/office/:id/edit', (s) => OfficeFormScreen(officeId: s.pathParameters['id'])),
      page(
        '/collector/office/:id/new-account',
        (s) => FacultyAccountFormScreen(officeId: s.pathParameters['id']!),
      ),
      page(
        '/collector/collection/:id',
        (s) => CollectionDetailsScreen(collectionId: s.pathParameters['id']!),
      ),
      page(AppRoutes.collectorSettings, (_) => const SettingsScreen()),
      page(AppRoutes.collectorLeaderboard, (_) => const LeaderboardScreen()),

      // ---------------- Faculty Office ----------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => FacultyShell(navigationShell: shell),
        branches: [
          tab(AppRoutes.facultyDashboard, const FacultyDashboardScreen()),
          tab(AppRoutes.facultySchedules, const FacultyScheduleScreen()),
          tab(AppRoutes.facultyLeaderboard, const LeaderboardScreen()),
          tab(AppRoutes.facultyNotifications, const NotificationFeedScreen()),
          tab(AppRoutes.facultyProfile, const ProfileScreen()),
        ],
      ),
      page('/faculty/schedule/:id', (s) => ScheduleDetailsScreen(scheduleId: s.pathParameters['id']!)),
      page(
        '/faculty/collection/:id',
        (s) => CollectionDetailsScreen(collectionId: s.pathParameters['id']!),
      ),
      page(
        '/faculty/notification/:id',
        (s) => NotificationDetailsScreen(notificationId: s.pathParameters['id']!),
      ),
      page(AppRoutes.facultyPoints, (_) => const PointsHistoryScreen()),
      page(AppRoutes.facultyPerformance, (_) => const PerformanceScreen()),
      page(AppRoutes.facultySettings, (_) => const SettingsScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Page not found')),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
