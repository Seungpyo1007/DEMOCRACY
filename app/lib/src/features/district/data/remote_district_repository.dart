import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';

/// The district profile from the BFF, parsed by the same fromJson the
/// fixture goes through.
class RemoteDistrictRepository implements DistrictRepository {
  const RemoteDistrictRepository(this.client);

  final BffClient client;

  @override
  Future<DistrictProfile> loadProfile(String districtId) async {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/profile',
      cacheable: true,
    );
    return DistrictProfile.fromJson(response.data);
  }
}
