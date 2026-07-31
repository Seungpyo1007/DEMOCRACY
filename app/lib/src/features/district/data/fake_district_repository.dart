import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';

/// Serves the bundled sample district.
///
/// Parsing runs through the same DistrictProfile.fromJson the real client will
/// use, so the provenance checks are exercised by every run rather than only
/// once a network layer exists.
class FakeDistrictRepository implements DistrictRepository {
  const FakeDistrictRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<DistrictProfile> loadProfile(String districtId) async {
    final payload = await loader.load('district_$districtId');
    return DistrictProfile.fromJson(payload);
  }
}
