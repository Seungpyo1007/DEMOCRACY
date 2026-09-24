import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/history/data/fake_history_repository.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:democracy/src/features/history/domain/history_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real client is wired.
final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => const FakeHistoryRepository(),
);

/// The history of whichever district the address state currently holds.
///
/// Keyed through districtProvider like every other feature, so a district
/// change refreshes this tab along with the rest.
final historyRecordProvider = FutureProvider<HistoryRecord>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(historyRepositoryProvider).loadHistory(district.id);
});
