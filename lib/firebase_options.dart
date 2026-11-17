// PLACEHOLDER — replace by running the FlutterFire CLI from the project root:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=<your-firebase-project-id> --platforms=android,ios
//
// `flutterfire configure` overwrites this file with your project's real
// options and adds google-services.json / GoogleService-Info.plist.
// These options are public client identifiers, not secrets. Never put a
// service-account key in the Flutter app.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run `flutterfire configure` to generate '
      'lib/firebase_options.dart for your Firebase project.',
    );
  }
}
