import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/emulator_config.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (EmulatorConfig.enabled) {
      await Firebase.initializeApp(options: EmulatorConfig.options);
      await EmulatorConfig.connect();
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    runApp(_FirebaseSetupErrorApp(error: e));
    return;
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(
    ProviderScope(
      // Firestore listeners already recover from connectivity loss; surface
      // other errors (e.g. permission-denied) immediately instead of retrying.
      retry: (_, _) => null,
      child: const ELabayApp(),
    ),
  );
}

/// Shown when Firebase has not been configured (see README "Firebase setup").
class _FirebaseSetupErrorApp extends StatelessWidget {
  const _FirebaseSetupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 56),
                const SizedBox(height: 16),
                Text('Firebase setup required',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  'E-Labay could not connect to Firebase.\n\n$error',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
