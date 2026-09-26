import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:democracy/src/features/history/domain/history_repository.dart';

/// Serves the bundled sample history.
///
/// Parsing runs through the same HistoryRecord.fromJson the real client will
/// use, so the provenance checks are exercised by every run rather than only
/// once a network layer exists.
class FakeHistoryRepository implements HistoryRepository {
  const FakeHistoryRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<HistoryRecord> loadHistory(String districtId) async {
    final payload = await loader.load('history_$districtId');
    return HistoryRecord.fromJson(payload);
  }
}
