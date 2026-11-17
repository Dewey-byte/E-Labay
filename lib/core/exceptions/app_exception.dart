import 'package:firebase_auth/firebase_auth.dart';

/// A user-presentable error. Use [AppException.from] to translate Firebase
/// errors into friendly messages.
class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;

  static AppException from(Object error) {
    if (error is AppException) return error;
    if (error is FirebaseAuthException) return _auth(error);
    if (error is FirebaseException) return _firebase(error);
    if (error is FormatException) return AppException(error.message);
    return const AppException('Something went wrong. Please try again.');
  }

  static String messageOf(Object error) => from(error).message;

  static AppException _auth(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return AppException('An account with this email already exists.', code: e.code);
      case 'invalid-email':
        return AppException('That email address is not valid.', code: e.code);
      case 'user-disabled':
        return AppException(
          'This account has been deactivated. Please contact the campus Collector.',
          code: e.code,
        );
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return AppException('Incorrect email or password.', code: e.code);
      case 'too-many-requests':
        return AppException(
          'Too many attempts. Please wait a moment and try again.',
          code: e.code,
        );
      case 'network-request-failed':
        return AppException(
          'No internet connection. E-Labay needs to be online.',
          code: e.code,
        );
      case 'requires-recent-login':
        return AppException('Please sign in again to continue.', code: e.code);
      case 'weak-password':
        return AppException('Choose a stronger password.', code: e.code);
      default:
        return AppException(e.message ?? 'Authentication failed.', code: e.code);
    }
  }


  static AppException _firebase(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return AppException('You do not have access to this information.', code: e.code);
      case 'unavailable':
        return AppException(
          'You appear to be offline. E-Labay needs an internet connection.',
          code: e.code,
        );
      case 'failed-precondition':
        return AppException(
          'A required database index is still being built. Please try again shortly.',
          code: e.code,
        );
      case 'not-found':
      case 'object-not-found':
        return AppException('The requested record no longer exists.', code: e.code);
      case 'unauthorized':
        return AppException('You are not allowed to upload this file.', code: e.code);
      default:
        return AppException(e.message ?? 'A server error occurred.', code: e.code);
    }
  }
}
