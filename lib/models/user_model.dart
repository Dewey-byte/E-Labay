import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_utils.dart';
import 'enums.dart';

/// `users/{uid}` — profile and role of an authenticated E-Labay user.
///
/// `role`, `officeId` and `isActive` are written only by trusted backend code
/// (Cloud Functions / admin scripts); security rules reject client changes.
class AppUser {
  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    this.officeId,
    this.profileImage,
    this.isActive = true,
    this.pushEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String fullName;
  final String email;
  final UserRole role;
  final String? officeId;
  final String? profileImage;
  final bool isActive;
  final bool pushEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCollector => role == UserRole.collector;
  bool get isFaculty => role == UserRole.faculty;

  String get displayName => fullName.isNotEmpty ? fullName : email;

  /// Throws [FormatException] when the stored role is missing or unknown so
  /// that the session layer can reject the profile.
  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    final role = UserRole.tryParse(data['role'] as String?);
    if (role == null) {
      throw const FormatException('This account has no valid E-Labay role.');
    }
    return AppUser(
      uid: id,
      fullName: readString(data['fullName']),
      email: readString(data['email']),
      role: role,
      officeId: readNullableString(data['officeId']),
      profileImage: readNullableString(data['profileImage']),
      isActive: data['isActive'] != false,
      pushEnabled: data['pushEnabled'] != false,
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppUser.fromMap(doc.id, doc.data() ?? const {});
}
