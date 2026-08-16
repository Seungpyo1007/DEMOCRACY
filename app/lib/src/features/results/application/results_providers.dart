import 'dart:async';

import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/features/results/data/fake_results_repository.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real SSE client is wired.
final resultsRepositoryProvider = Provider<ResultsRepository>(
  (ref) => const FakeResultsRepository(),
);

/// The one place an embargo is applied.
///
/// Every path from a repository to the results screen runs through here, and
/// [PublicationGate.apply] is the only producer of [ElectionResults], so there
/// is no second route a future screen could take.
final electionResultsProvider = StreamProvider<ElectionResults>((ref) {
  final district = ref.watch(districtProvider);

  if (district == null) {
    return const Stream.empty();
  }

  final clock = ref.watch(clockProvider);

  // A verdict is about *now*, but a stream can go quiet either side of a
  // deadline: one that last spoke on the seventh day out would keep showing
  // polls into the blackout, and one that stopped at 17:59 would keep showing
  // a count past closing. Re-evaluate when the next deadline arrives.
  Timer? boundary;
  ref.onDispose(() => boundary?.cancel());

  return ref.watch(resultsRepositoryProvider).watch(district.id).map((raw) {
    final now = clock.now();
    boundary?.cancel();
    final next = PublicationGate.nextBoundary(raw.schedule, now: now);
    if (next != null) {
      boundary = Timer(next.difference(now), ref.invalidateSelf);
    }
    return PublicationGate.apply(raw, now: now);
  });
});
