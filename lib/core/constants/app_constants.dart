/// App-wide constants shared by the UI, repositories and services.
///
/// Keep the Firestore collection names and Cloud Function names in sync with
/// `functions/src/config.ts`.
class AppConstants {
  AppConstants._();

  static const appName = 'E-Labay';
  static const appTagline = 'Campus Waste Management & Collection Tracking';

  /// Region the Cloud Functions are deployed to. Must match `REGION` in
  /// `functions/src/config.ts`.
  static const functionsRegion = 'asia-southeast1';

  /// Default page size for paginated history lists.
  static const pageSize = 20;

  /// Maximum number of evidence photos per collection assessment.
  static const maxEvidencePhotos = 3;

  /// Minimum password length for provisioned accounts.
  static const minPasswordLength = 8;
}

class FirestoreCollections {
  FirestoreCollections._();

  static const users = 'users';
  static const offices = 'offices';
  static const schedules = 'schedules';
  static const collections = 'collections';
  static const notifications = 'notifications';
  static const pointTransactions = 'point_transactions';
  static const config = 'config';

  /// Sub-collection of `users/{uid}` holding that user's FCM device tokens.
  static const fcmTokens = 'fcmTokens';

  /// Document id inside [config] that holds the scoring rules.
  static const scoringConfigDoc = 'scoring';
}

class CloudFunctionNames {
  CloudFunctionNames._();

  static const provisionFacultyAccount = 'provisionFacultyAccount';
  static const setAccountStatus = 'setAccountStatus';
  static const submitCollectionAssessment = 'submitCollectionAssessment';
  static const recalculateLeaderboard = 'recalculateLeaderboard';
}

class StoragePaths {
  StoragePaths._();

  /// `collections/{officeId}/{scheduleId}/{fileName}`
  static String evidence(String officeId, String scheduleId, String fileName) =>
      'collections/$officeId/$scheduleId/$fileName';

  /// `profile_images/{uid}/{fileName}`
  static String profileImage(String uid, String fileName) =>
      'profile_images/$uid/$fileName';
}
