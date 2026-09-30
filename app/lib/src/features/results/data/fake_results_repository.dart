import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';

/// Stands in for SSE on election day and a slow poll off it.
///
/// Counts only ever rise, so each tick nudges every district toward fully
/// counted rather than re-randomising. A stand-in that let a share fall would
/// let a bug that does the same thing pass unnoticed.
class FakeResultsRepository implements ResultsRepository {
  const FakeResultsRepository({
    this.loader = const FixtureLoader(),
    this.interval = const Duration(seconds: 30),
    this.ticks = 3,
  });

  final FixtureLoader loader;

  /// The guide's election-day cadence. The real one is set by a server header
  /// so the client cannot decide to poll harder than the count can bear.
  final Duration interval;

  final int ticks;

  @override
  Stream<RawElectionResults> watch(String districtId) async* {
    final payload = await loader.load('results_$districtId');
    var results = RawElectionResults.fromJson(payload);
    yield results;

    if (!results.live) {
      return;
    }

    for (var tick = 0; tick < ticks; tick++) {
      await Future<void>.delayed(interval);
      results = _advance(results);
      yield results;
    }
  }

  RawElectionResults _advance(RawElectionResults results) {
    DistrictCount advanceDistrict(DistrictCount district) {
      final counted = (district.countedShare + 6).clamp(0.0, 100.0);
      return DistrictCount(
        districtId: district.districtId,
        districtName: district.districtName,
        countedShare: counted,
        // The shares themselves hold still. What a longer count changes is
        // confidence, and inventing movement would be the fake asserting
        // something about an election.
        tallies: district.tallies,
        source: district.source,
      );
    }

    final districts = results.districts.map(advanceDistrict).toList();
    final overall =
        districts.fold<double>(0, (sum, d) => sum + d.countedShare) /
        (districts.isEmpty ? 1 : districts.length);

    return RawElectionResults(
      schedule: results.schedule,
      electionName: results.electionName,
      overallCountedShare: overall,
      districts: List.unmodifiable(districts),
      historical: results.historical,
      polls: results.polls,
      live: overall < 100,
    );
  }
}
