import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collection_model.dart';
import '../repositories/collection_repository.dart';

final collectionProvider = StreamProvider.autoDispose.family<CollectionRecord?, String>(
  (ref, id) => ref.watch(collectionRepositoryProvider).watchCollection(id),
);

/// Latest collections campus-wide (Collector dashboard activity feed).
final recentCollectionsProvider = StreamProvider.autoDispose<List<CollectionRecord>>(
  (ref) => ref.watch(collectionRepositoryProvider).watchRecent(limit: 5),
);

/// Recent collections of one office; the record type is `(officeId, limit)`.
final officeCollectionsProvider =
    StreamProvider.autoDispose.family<List<CollectionRecord>, (String, int)>(
  (ref, args) =>
      ref.watch(collectionRepositoryProvider).watchRecent(officeId: args.$1, limit: args.$2),
);

/// Collections completed over the last 7 days (dashboard chart).
final weeklyCollectionsProvider = StreamProvider.autoDispose<List<CollectionRecord>>((ref) {
  final now = DateTime.now();
  final since = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  return ref.watch(collectionRepositoryProvider).watchSince(since);
});
