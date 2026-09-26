import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';

/// Stands in for the server-mediated direction run.
///
/// Reads the same `fromJson` the real client will, so a payload missing its
/// provenance fails here exactly as it would in production.
class FakeDirectionRepository implements DirectionRepository {
  const FakeDirectionRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<DirectionReport> loadReport(String districtId) async {
    final payload = await loader.load('ai_direction_$districtId');
    return DirectionReport.fromJson(payload);
  }
}
