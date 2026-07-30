import 'package:democracy/src/core/auth/address_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const district = DistrictRef(
    id: 'fixture-seoul-mapo-b',
    displayName: '서울 마포구 을',
  );

  test('verified state requires a non-empty opaque proof token', () {
    expect(
      () => ResidencyVerificationProof(
        opaqueToken: '   ',
        verifiedAt: DateTime.utc(2026, 7, 30),
      ),
      throwsArgumentError,
    );
  });

  test('pending and verified states expose different write access', () {
    const pending = AddressState.pending(district: district);
    final verified = AddressState.verified(
      district: district,
      proof: ResidencyVerificationProof(
        opaqueToken: 'fixture-opaque-token',
        verifiedAt: DateTime.utc(2026, 7, 30),
      ),
    );

    expect(pending.isVerified, isFalse);
    expect(verified.isVerified, isTrue);
  });
}
