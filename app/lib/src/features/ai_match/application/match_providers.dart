import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, in a live build, with the on-device model.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => const FakeMatchRepository(),
);

/// Who the match is against, known before the result arrives so the title
/// can say it: candidates in a fixture build (and at election time), the
/// sitting member in a live build between elections.
final matchSubjectProvider = Provider<MatchSubject>(
  (ref) => MatchSubject.candidates,
);

/// The reader's profile as a match query: the policy chips are the axes, the
/// rest is context.
MatchQuery matchQueryFor(ResidentProfile profile) {
  final policy = profile.policyTags;
  return MatchQuery(
    interests: [
      for (final tag in ResidentProfile.availableTags)
        if (policy.contains(tag)) tag,
    ],
    context: [
      for (final tag in ResidentProfile.availableTags)
        if (profile.tags.contains(tag) && !policy.contains(tag)) tag,
    ],
  );
}

/// Never retried on its own: a failed on-device run failed on this input with
/// this model, and running it again unasked would only spend the battery on
/// the same answer. The screen offers 다시 시도 where it could help.
Duration? noRetry(int retryCount, Object error) => null;

final matchReportProvider = FutureProvider<MatchReport>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  final tags = ref.watch(residentProfileProvider.select((p) => p.tags));
  final query = matchQueryFor(ResidentProfile(tags: tags));
  return ref
      .watch(matchRepositoryProvider)
      .loadReport(district.id, query: query);
}, retry: noRetry);

/// What a run still going has produced, where the repository reports it.
final matchProgressProvider = StreamProvider.autoDispose<MatchProgress>((ref) {
  final repository = ref.watch(matchRepositoryProvider);
  return repository is MatchProgressSource
      ? (repository as MatchProgressSource).progress
      : const Stream.empty();
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
