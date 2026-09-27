import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `가상 의원 · 서울 마포구 을` -- whose seat the community is talking about.
///
/// Shared by the hub's header and the compose sheet so the sheet names the
/// same seat the reader was looking at. The incumbent's name comes from the
/// district profile and is left out until it has loaded, rather than holding
/// the header back: the district alone is still a true kicker.
String? communityKicker(WidgetRef ref) {
  final district = ref.watch(addressControllerProvider).district;
  if (district == null) {
    return null;
  }

  final incumbent = ref.watch(districtProfileProvider).value?.incumbent?.name;
  if (incumbent == null || incumbent.isEmpty) {
    return district.displayName;
  }
  return '$incumbent · ${district.displayName}';
}
