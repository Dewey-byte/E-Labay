import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
import '../core/services/emulator_config.dart';
import '../core/services/firebase_providers.dart';
import '../models/enums.dart';
import '../models/office_model.dart';
import '../models/user_model.dart';

class ProvisionResult {
  const ProvisionResult({required this.officeId, required this.uid});
  final String officeId;
  final String uid;
}

/// Faculty offices and their login accounts.
class OfficeRepository {
  OfficeRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _offices =>
      _db.collection(FirestoreCollections.offices);

  Stream<List<Office>> watchOffices() => _offices
      .orderBy('officeName')
      .snapshots()
      .map((s) => s.docs.map(Office.fromDoc).toList());

  Stream<Office?> watchOffice(String officeId) => _offices
      .doc(officeId)
      .snapshots()
      .map((doc) => doc.exists ? Office.fromDoc(doc) : null);

  /// Collectors may edit descriptive fields only; totals change only through
  /// verified assessments.
  Future<void> updateOfficeDetails(
    String officeId, {
    required String officeName,
    required String building,
    required String description,
  }) async {
    try {
      await _offices.doc(officeId).update({
        'officeName': officeName.trim(),
        'building': building.trim(),
        'description': description.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Faculty accounts linked to an office (visible to Collectors only).
  Stream<List<AppUser>> watchOfficeAccounts(String officeId) => _db
      .collection(FirestoreCollections.users)
      .where('officeId', isEqualTo: officeId)
      .where('role', isEqualTo: UserRole.faculty.value)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  /// Creates a Faculty Office login and its profile — and, when [officeId] is
  /// null, the office itself. Runs as the signed-in Collector: the Auth
  /// account is created through a temporary secondary Firebase app so the
  /// Collector stays signed in, then the office and profile are written in
  /// one batch that security rules allow only for Collectors. If that write
  /// fails, the new Auth account is deleted again.
  Future<ProvisionResult> provisionFacultyAccount({
    String? officeId,
    String? officeName,
    String? building,
    String? description,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final collectorUid = _auth.currentUser?.uid;
    if (collectorUid == null) throw const AppException('You are not signed in.');

    final targetOffice = officeId == null ? _offices.doc() : _offices.doc(officeId);
    if (officeId == null) {
      final duplicate = await _offices.where('officeName', isEqualTo: officeName!.trim()).limit(1).get();
      if (duplicate.docs.isNotEmpty) {
        throw AppException('An office named "${officeName.trim()}" already exists.');
      }
    } else if (!(await targetOffice.get()).exists) {
      throw const AppException('That office does not exist.');
    }

    FirebaseApp? secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'provisioning-${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      if (EmulatorConfig.enabled) {
        await secondaryAuth.useAuthEmulator(EmulatorConfig.host, 9099);
      }
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final newUser = credential.user!;
      try {
        final batch = _db.batch();
        if (officeId == null) {
          batch.set(targetOffice, {
            'officeId': targetOffice.id,
            'officeName': officeName!.trim(),
            'building': building!.trim(),
            'description': (description ?? '').trim(),
            'totalPoints': 0,
            'totalCollections': 0,
            'totalProperSegregations': 0,
            'totalAssessments': 0,
            'categoryStats': <String, dynamic>{},
            'createdBy': collectorUid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        batch.set(_db.collection(FirestoreCollections.users).doc(newUser.uid), {
          'uid': newUser.uid,
          'fullName': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'role': UserRole.faculty.value,
          'officeId': targetOffice.id,
          'profileImage': null,
          'isActive': true,
          'pushEnabled': true,
          'createdBy': collectorUid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } catch (e) {
        await newUser.delete().catchError((_) {});
        rethrow;
      }
      await secondaryAuth.signOut();
      return ProvisionResult(officeId: targetOffice.id, uid: newUser.uid);
    } catch (e) {
      throw AppException.from(e);
    } finally {
      await secondary?.delete();
    }
  }

  /// Deactivated accounts are locked out of all data by the security rules
  /// and signed out by the app.
  Future<void> setAccountStatus({required String uid, required bool isActive}) async {
    try {
      await _db.collection(FirestoreCollections.users).doc(uid).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final officeRepositoryProvider = Provider<OfficeRepository>(
  (ref) => OfficeRepository(ref.watch(firestoreProvider), ref.watch(firebaseAuthProvider)),
);
