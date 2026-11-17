import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/point_transaction_model.dart';
import '../models/scoring_config.dart';
import '../repositories/config_repository.dart';
import '../repositories/point_transaction_repository.dart';

/// Point transactions of an office; argument is `(officeId, limit)`.
final pointTransactionsProvider =
    StreamProvider.autoDispose.family<List<PointTransaction>, (String, int)>(
  (ref, args) => ref
      .watch(pointTransactionRepositoryProvider)
      .watchTransactions(args.$1, limit: args.$2),
);

/// Current scoring rules (falls back to defaults if not configured yet).
final scoringConfigProvider = StreamProvider.autoDispose<ScoringConfig>(
  (ref) => ref.watch(configRepositoryProvider).watchScoringConfig(),
);
