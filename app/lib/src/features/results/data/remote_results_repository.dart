import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';

/// Election results from the BFF, parsed by the same fromJson the fixture
/// goes through -- so a payload that is silent about the schedule, or a
/// count without a source, fails here exactly as it does in the sample.
///
/// Off election the BFF serves the last general election's final count,
/// which does not change, so [watch] fetches once and completes. Election
/// day will keep this stream open instead -- SSE, or a poll at a cadence the
/// server sets -- without the screen knowing which; the stream is already
/// that seam.
class RemoteResultsRepository implements ResultsRepository {
  const RemoteResultsRepository(this.client);

  final BffClient client;

  @override
  Stream<RawElectionResults> watch(String districtId) async* {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/results',
      // Safe while the payload is a final count. A live count must not fall
      // back to one kept on disk: it would be stale the moment it was kept.
      cacheable: true,
    );
    yield RawElectionResults.fromJson(response.data);
  }
}
