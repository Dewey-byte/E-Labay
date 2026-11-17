import 'emulator_config.dart';

/// Build-time feature switches.
class FeatureFlags {
  FeatureFlags._();

  /// Evidence photos and profile pictures need Cloud Storage, which requires
  /// the Blaze plan. Enable with `--dart-define=ENABLE_PHOTO_UPLOADS=true`
  /// after upgrading and deploying `storage.rules`. Always on with the local
  /// emulators.
  static bool get photoUploads =>
      EmulatorConfig.enabled || const bool.fromEnvironment('ENABLE_PHOTO_UPLOADS');
}
