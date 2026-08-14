import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real client is wired.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => const FakeMatchRepository(),
);

final matchReportProvider = FutureProvider<MatchReport>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(matchRepositoryProvider).loadReport(district.id);
});

/// The reasoning for one candidate, as it arrives.
final matchReasoningProvider = StreamProvider.family<String, String>((
  ref,
  candidateId,
) {
  final district = ref.watch(districtProvider);

  if (district == null) {
    return const Stream.empty();
  }

  return ref
      .watch(matchRepositoryProvider)
      .streamReasoning(district.id, candidateId);
});
