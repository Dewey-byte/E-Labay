import '../constants/app_constants.dart';

/// Form field validators. Each returns `null` when the value is valid.
class Validators {
  Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, [String field = 'This field']) =>
      (value == null || value.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!_email.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < AppConstants.minPasswordLength) {
      return 'Use at least ${AppConstants.minPasswordLength} characters';
    }
    return null;
  }

  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Password is required' : null;

  static String? maxLength(String? value, int max, [String field = 'This field']) =>
      (value != null && value.trim().length > max)
          ? '$field must be at most $max characters'
          : null;

  static String? name(String? value, [String field = 'Name']) =>
      required(value, field) ?? maxLength(value, 80, field);
}
