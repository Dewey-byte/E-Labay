import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/office_model.dart';
import '../models/user_model.dart';
import '../repositories/office_repository.dart';
import 'auth_provider.dart';

/// All offices, alphabetical (Collector views and pickers).
final officesProvider = StreamProvider.autoDispose<List<Office>>(
  (ref) => ref.watch(officeRepositoryProvider).watchOffices(),
);

final officeProvider = StreamProvider.autoDispose.family<Office?, String>(
  (ref, officeId) => ref.watch(officeRepositoryProvider).watchOffice(officeId),
);

/// The signed-in Faculty Office's own office.
final myOfficeProvider = StreamProvider.autoDispose<Office?>((ref) {
  final officeId = ref.watch(currentUserProvider)?.officeId;
  if (officeId == null) return Stream.value(null);
  return ref.watch(officeRepositoryProvider).watchOffice(officeId);
});

final officeAccountsProvider = StreamProvider.autoDispose.family<List<AppUser>, String>(
  (ref, officeId) => ref.watch(officeRepositoryProvider).watchOfficeAccounts(officeId),
);
