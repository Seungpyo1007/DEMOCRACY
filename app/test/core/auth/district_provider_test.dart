import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mapo = DistrictRef(id: 'fixture-seoul-mapo-b', displayName: '서울 마포구 을');
const _seodaemun = DistrictRef(
  id: 'fixture-seoul-seodaemun-a',
  displayName: '서울 서대문구 갑',
);

void main() {
  test('starts empty and follows the address state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(districtProvider), isNull);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _mapo);
    expect(container.read(districtProvider)?.id, _mapo.id);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _seodaemun);
    expect(container.read(districtProvider)?.id, _seodaemun.id);
  });

  // Every feature provider watches this one, so a rebuild here is a rebuild
  // everywhere. Verification changing without the district changing must not
  // trigger one, or every screen refetches when someone finishes onboarding.
  test('does not rebuild when only the verification changes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _mapo);

    var rebuilds = 0;
    container.listen(districtProvider, (previous, next) => rebuilds++);

    container
        .read(addressControllerProvider.notifier)
        .acceptVerification(
          district: _mapo,
          proof: ResidencyVerificationProof(
            opaqueToken: 'fixture-token',
            verifiedAt: DateTime.utc(2026, 7, 30),
          ),
        );

    expect(container.read(addressControllerProvider).isVerified, isTrue);
    expect(rebuilds, 0);
  });
}
