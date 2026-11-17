import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/exceptions/app_exception.dart';
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
  OfficeRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

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

  /// Collectors may edit descriptive fields only; counters are backend-owned.
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

  /// Creates a Faculty Office login (and, when [officeId] is null, a new office)
  /// through the trusted `provisionFacultyAccount` Cloud Function.
  Future<ProvisionResult> provisionFacultyAccount({
    String? officeId,
    String? officeName,
    String? building,
    String? description,
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final result = await _functions
          .httpsCallable(CloudFunctionNames.provisionFacultyAccount)
          .call<Map<String, dynamic>>({
        'officeId': ?officeId,
        if (officeId == null)
          'office': {
            'officeName': officeName?.trim(),
            'building': building?.trim(),
            'description': description?.trim() ?? '',
          },
        'account': {
          'fullName': fullName.trim(),
          'email': email.trim(),
          'password': password,
        },
      });
      final data = Map<String, dynamic>.from(result.data);
      return ProvisionResult(
        officeId: data['officeId'] as String,
        uid: data['uid'] as String,
      );
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> setAccountStatus({required String uid, required bool isActive}) async {
    try {
      await _functions
          .httpsCallable(CloudFunctionNames.setAccountStatus)
          .call<Map<String, dynamic>>({'uid': uid, 'isActive': isActive});
    } catch (e) {
      throw AppException.from(e);
    }
  }
}

final officeRepositoryProvider = Provider<OfficeRepository>(
  (ref) => OfficeRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider)),
);
