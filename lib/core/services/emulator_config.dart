import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/app_constants.dart';

/// Local development against the Firebase Emulator Suite (`npm run emulators`).
///
/// Enable with `flutter run --dart-define=USE_FIREBASE_EMULATORS=true`.
/// The Android emulator reaches the host machine at 10.0.2.2; override with
/// `--dart-define=FIREBASE_EMULATOR_HOST=<ip>` for a physical device.
/// Never enabled in normal builds.
class EmulatorConfig {
  EmulatorConfig._();

  static const enabled = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  static const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '10.0.2.2');

  /// Demo-project options; the emulators accept any values for `demo-*`.
  static const options = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-elabay',
    storageBucket: 'demo-elabay.appspot.com',
  );

  static Future<void> connect() async {
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion).useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }
}
