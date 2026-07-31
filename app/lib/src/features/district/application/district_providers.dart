import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real client is wired.
final districtRepositoryProvider = Provider<DistrictRepository>(
  (ref) => const FakeDistrictRepository(),
);

/// The profile for whichever district the address state currently holds.
///
/// Watching addressControllerProvider is what makes a district change refresh
/// every screen at once, without any of them subscribing to the change.
final districtProfileProvider = FutureProvider<DistrictProfile>((ref) async {
  final district = ref.watch(
    addressControllerProvider.select((state) => state.district),
  );

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(districtRepositoryProvider).loadProfile(district.id);
});
