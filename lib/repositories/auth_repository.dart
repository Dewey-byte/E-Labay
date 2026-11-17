import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/firebase_providers.dart';
import '../models/user_model.dart';

/// Authentication and the signed-in user's own profile.
///
/// Accounts are never self-registered: Collectors are bootstrapped through an
/// admin script and Faculty Office accounts are provisioned by a Collector via
/// the `provisionFacultyAccount` Cloud Function.
class AuthRepository {
  AuthRepository(this._auth, this._db, this._storage);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection(FirestoreCollections.users).doc(uid);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Stream<AppUser?> watchUserProfile(String uid) => _userDoc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AppException('You are not signed in.');
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Users may only edit these profile fields; rules reject anything else.
  Future<void> updateProfile(String uid, {required String fullName}) async {
    try {
      await _userDoc(uid).update({
        'fullName': fullName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> setPushEnabled(String uid, bool enabled) async {
    try {
      await _userDoc(uid).update({
        'pushEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> uploadProfileImage(String uid, File file) async {
    try {
      final ref = _storage.ref(
        StoragePaths.profileImage(uid, 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg'),
      );
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await _userDoc(uid).update({
        'profileImage': url,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
    ref.watch(storageProvider),
  ),
);
