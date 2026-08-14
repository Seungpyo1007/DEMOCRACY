import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';

/// Stands in for the server-mediated model run.
///
/// The reasoning arrives as a stream of growing prefixes because that is the
/// shape the real one has, and building the screen against a finished string
/// would hide every question a partial answer raises -- what to show while it
/// is arriving, and what the reader is looking at if it stops early.
class FakeMatchRepository implements MatchRepository {
  const FakeMatchRepository({
    this.loader = const FixtureLoader(),
    this.tokenDelay = const Duration(milliseconds: 40),
  });

  final FixtureLoader loader;
  final Duration tokenDelay;

  @override
  Future<MatchReport> loadReport(String districtId) async {
    final payload = await loader.load('ai_match_$districtId');
    return MatchReport.fromJson(payload);
  }

  @override
  Stream<String> streamReasoning(String districtId, String candidateId) async* {
    final report = await loadReport(districtId);
    final match = report.matches
        .where((candidate) => candidate.candidateId == candidateId)
        .firstOrNull;

    if (match == null || match.reasons.isEmpty) {
      return;
    }

    final full = match.reasons.map((reason) => reason.text).join(' ');
    final buffer = StringBuffer();

    // Word by word: a Korean sentence broken mid-character reads as a
    // rendering fault rather than as generation in progress.
    for (final word in full.split(' ')) {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(word);
      yield buffer.toString();
      await Future<void>.delayed(tokenDelay);
    }
  }
}
