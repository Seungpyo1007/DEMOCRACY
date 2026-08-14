import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/results/data/fake_results_repository.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real SSE client is wired.
final resultsRepositoryProvider = Provider<ResultsRepository>(
  (ref) => const FakeResultsRepository(),
);

final electionResultsProvider = StreamProvider<ElectionResults>((ref) {
  final district = ref.watch(districtProvider);

  if (district == null) {
    return const Stream.empty();
  }

  return ref.watch(resultsRepositoryProvider).watch(district.id);
});
