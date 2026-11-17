import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/exceptions/app_exception.dart';
import '../core/services/push_notification_service.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

/// Firebase Auth state.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// `users/{uid}` profile of the signed-in user (null when signed out or when
/// the profile document does not exist).
final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchUserProfile(user.uid);
});

/// High-level session state that drives role-based routing.
sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in, but the account cannot use the app (no profile, unknown role or
/// deactivated). The app signs the user out and shows [message].
class SessionInvalid extends SessionState {
  const SessionInvalid(this.message);
  final String message;
}

class SessionReady extends SessionState {
  const SessionReady(this.user);
  final AppUser user;
}

final sessionProvider = Provider<SessionState>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.when(
    loading: () => const SessionLoading(),
    error: (_, _) => const SessionSignedOut(),
    data: (user) {
      if (user == null) return const SessionSignedOut();
      final profile = ref.watch(currentUserProfileProvider);
      return profile.when(
        loading: () => const SessionLoading(),
        error: (e, _) => SessionInvalid(AppException.messageOf(e)),
        data: (p) {
          if (p == null) {
            return const SessionInvalid(
              'No E-Labay profile is linked to this account. Please contact the campus Collector.',
            );
          }
          if (!p.isActive) {
            return const SessionInvalid(
              'This account has been deactivated. Please contact the campus Collector.',
            );
          }
          if (p.isFaculty && p.officeId == null) {
            return const SessionInvalid(
              'This Faculty Office account is not linked to an office yet.',
            );
          }
          return SessionReady(p);
        },
      );
    },
  );
});

/// The signed-in, validated user, or null.
final currentUserProvider = Provider<AppUser?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionReady ? session.user : null;
});

/// Session actions that span several services.
class SessionController {
  SessionController(this._ref);
  final Ref _ref;

  /// Unregisters this device from push notifications, then signs out.
  Future<void> signOut() async {
    await _ref.read(pushNotificationServiceProvider).unregister();
    await _ref.read(authRepositoryProvider).signOut();
  }
}

final sessionControllerProvider = Provider<SessionController>(SessionController.new);

/// One-shot message shown on the login screen (e.g. why the user was signed
/// out).
class AuthNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String? message) => state = message;
  void clear() => state = null;
}

final authNoticeProvider = NotifierProvider<AuthNotice, String?>(AuthNotice.new);
