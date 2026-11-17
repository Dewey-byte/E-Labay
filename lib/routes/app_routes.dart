/// Route paths. Collector routes live under `/collector`, Faculty Office
/// routes under `/faculty`; the router redirects users away from the other
/// role's area.
class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const login = '/login';

  // Collector — bottom navigation tabs
  static const collectorDashboard = '/collector/dashboard';
  static const collectorSchedules = '/collector/schedules';
  static const collectorOffices = '/collector/offices';
  static const collectorHistory = '/collector/history';
  static const collectorProfile = '/collector/profile';

  // Collector — full-screen pages
  static const collectorNewSchedule = '/collector/new-schedule';
  static const collectorNewOffice = '/collector/new-office';
  static const collectorSettings = '/collector/settings';
  static String collectorSchedule(String id) => '/collector/schedule/$id';
  static String collectorEditSchedule(String id) => '/collector/schedule/$id/edit';
  static String collectorAssess(String id) => '/collector/schedule/$id/assess';
  static String collectorSubmitted(String id) => '/collector/schedule/$id/submitted';
  static String collectorOffice(String id) => '/collector/office/$id';
  static String collectorEditOffice(String id) => '/collector/office/$id/edit';
  static String collectorNewAccount(String id) => '/collector/office/$id/new-account';
  static String collectorCollection(String id) => '/collector/collection/$id';

  /// New schedule pre-filled with an office.
  static String collectorNewScheduleFor(String officeId) =>
      '$collectorNewSchedule?officeId=$officeId';

  // Faculty — bottom navigation tabs
  static const facultyDashboard = '/faculty/dashboard';
  static const facultySchedules = '/faculty/schedules';
  static const facultyLeaderboard = '/faculty/leaderboard';
  static const facultyNotifications = '/faculty/notifications';
  static const facultyProfile = '/faculty/profile';

  // Faculty — full-screen pages
  static const facultyPoints = '/faculty/points';
  static const facultyPerformance = '/faculty/performance';
  static const facultySettings = '/faculty/settings';
  static String facultySchedule(String id) => '/faculty/schedule/$id';
  static String facultyCollection(String id) => '/faculty/collection/$id';
  static String facultyNotification(String id) => '/faculty/notification/$id';
}
