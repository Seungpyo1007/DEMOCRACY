import 'package:democracy/src/features/district/domain/district_profile.dart';

/// What the district screens are allowed to depend on.
///
/// Screens talk to this and never to a transport, so swapping the fake for a
/// REST implementation later is a wiring change rather than a screen change.
abstract interface class DistrictRepository {
  Future<DistrictProfile> loadProfile(String districtId);
}
