import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'firebase_providers.dart';

/// Background/terminated message handler. Notification payloads are shown by
/// the OS automatically, so nothing else is required here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Registers this device for Firebase Cloud Messaging, stores its token under
/// `users/{uid}/fcmTokens/{token}` and exposes foreground messages and
/// notification taps as streams.
class PushNotificationService {
  PushNotificationService(this._messaging, this._db);

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];

  String? _uid;
  String? _token;

  /// Data payloads of notifications the user tapped while the app was in the
  /// background.
  Stream<Map<String, dynamic>> get onNotificationTap => _taps.stream;

  /// Messages received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage => _foreground.stream;

  /// Requests permission, saves the device token and starts listening.
  /// Returns the data payload of the notification that launched the app from
  /// a terminated state, if any.
  Future<Map<String, dynamic>?> register(String uid) async {
    if (_uid == uid) return null;
    await unregister();
    _uid = uid;

    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      _subs
        ..add(FirebaseMessaging.onMessage.listen(_foreground.add))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(m.data)));

      if (settings.authorizationStatus != AuthorizationStatus.denied) {
        // iOS: suppress the system banner in the foreground; the app shows
        // its own in-app banner instead.
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: true,
        );
        // Registration tokens are what the Admin SDK `send({token})` targets,
        // so the token API is used despite its deprecation in favour of FIDs.
        // ignore: deprecated_member_use
        final token = await _messaging.getToken();
        if (token != null) await _saveToken(uid, token);
        // ignore: deprecated_member_use
        _subs.add(_messaging.onTokenRefresh.listen((t) => _saveToken(uid, t)));
      }

      final initial = await _messaging.getInitialMessage();
      return initial?.data;
    } catch (e) {
      // Push is best-effort (e.g. iOS simulator without APNs); the in-app
      // Firestore feed still works.
      debugPrint('FCM registration failed: $e');
      return null;
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    _token = token;
    await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.fcmTokens)
        .doc(token)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes this device's token so the signed-out user stops receiving
  /// pushes. Must run before Firebase sign-out (rules require auth).
  Future<void> unregister() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    if (uid == null) return;
    try {
      if (token != null) {
        await _db
            .collection(FirestoreCollections.users)
            .doc(uid)
            .collection(FirestoreCollections.fcmTokens)
            .doc(token)
            .delete();
      }
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('FCM unregister failed: $e');
    }
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(ref.watch(messagingProvider), ref.watch(firestoreProvider)),
);
