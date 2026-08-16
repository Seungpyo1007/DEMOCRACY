import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

ResidencyVerificationProof _proof() => ResidencyVerificationProof(
  opaqueToken: 'server-issued-token',
  verifiedAt: DateTime.utc(2026, 5, 1, 9),
);

void main() {
  group('the round trip', () {
    test('carries a read-only district back', () {
      final restored = addressStateFromJson(
        addressStateToJson(const AddressState.readOnly(district: _district)),
      );

      expect(restored.status, AddressStatus.unverified);
      expect(restored.district?.id, _district.id);
      expect(restored.district?.displayName, _district.displayName);
    });

    test('carries a verification back intact', () {
      final proof = _proof();
      final restored = addressStateFromJson(
        addressStateToJson(
          AddressState.verified(district: _district, proof: proof),
        ),
      );

      expect(restored.isVerified, isTrue);
      expect(restored.verification?.opaqueToken, proof.opaqueToken);
      expect(restored.verification?.verifiedAt, proof.verifiedAt);
    });

    test('survives a launch with nothing set', () {
      final restored = addressStateFromJson(
        addressStateToJson(const AddressState.initial()),
      );

      expect(restored.district, isNull);
      expect(restored.isVerified, isFalse);
    });
  });

  group('what a restore refuses to reconstitute', () {
    // Restoring is not a way to acquire a status the server never granted.
    // A record that claims `verified` without a token it can show is a
    // downgrade, not a crash and not a free pass.
    test('a verified status with no proof comes back read-only', () {
      final restored = addressStateFromJson({
        'status': 'verified',
        'district': {'id': _district.id, 'displayName': _district.displayName},
      });

      expect(restored.isVerified, isFalse);
      expect(restored.status, AddressStatus.unverified);
      expect(restored.district?.id, _district.id);
    });

    test('a verified status with no district comes back read-only', () {
      final restored = addressStateFromJson({
        'status': 'verified',
        'verification': {
          'opaqueToken': 'server-issued-token',
          'verifiedAt': '2026-05-01T09:00:00.000Z',
        },
      });

      expect(restored.isVerified, isFalse);
      expect(restored.district, isNull);
    });

    // A request is in flight with a server that has no memory of the process
    // that made it. Resuming into it would leave a spinner no reply can end.
    test('a pending status comes back read-only', () {
      final restored = addressStateFromJson(
        addressStateToJson(const AddressState.pending(district: _district)),
      );

      expect(restored.status, AddressStatus.unverified);
      expect(restored.district?.id, _district.id);
    });

    test(
      'an unknown status is treated as unverified rather than thrown on',
      () {
        final restored = addressStateFromJson({
          'status': 'some-status-a-later-build-invented',
          'district': {
            'id': _district.id,
            'displayName': _district.displayName,
          },
        });

        expect(restored.status, AddressStatus.unverified);
        expect(restored.district?.id, _district.id);
      },
    );
  });

  group('the controller', () {
    ProviderContainer containerWith(InMemoryAddressStore store) {
      final container = ProviderContainer(
        overrides: [addressStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('persists a district chosen without verification', () async {
      final store = InMemoryAddressStore();
      final container = containerWith(store);

      container
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: _district);
      await pumpEventQueue();

      expect(store.current?.district?.id, _district.id);
    });

    test('persists a verification', () async {
      final store = InMemoryAddressStore();
      final container = containerWith(store);

      container
          .read(addressControllerProvider.notifier)
          .acceptVerification(district: _district, proof: _proof());
      await pumpEventQueue();

      expect(store.current?.isVerified, isTrue);
    });

    test('does not persist a request that is still in flight', () async {
      final store = InMemoryAddressStore();
      final container = containerWith(store);

      container
          .read(addressControllerProvider.notifier)
          .requestVerification(district: _district);
      await pumpEventQueue();

      expect(store.current, isNull);
    });

    // The state came from the store. Echoing it back is only a chance to
    // corrupt the record it was read from.
    test('a restore does not write back', () async {
      final store = InMemoryAddressStore();
      final container = containerWith(store);

      container
          .read(addressControllerProvider.notifier)
          .restore(const AddressState.readOnly(district: _district));
      await pumpEventQueue();

      expect(store.current, isNull);
      expect(container.read(districtProvider)?.id, _district.id);
    });

    // This is the defect the whole seam exists for: before it, a launch after
    // onboarding found no district and the router sent the resident straight
    // back through it.
    test('a launch with a stored session starts with a district', () async {
      final container = containerWith(
        InMemoryAddressStore(
          AddressState.verified(district: _district, proof: _proof()),
        ),
      );

      expect(
        container.read(districtProvider),
        isNull,
        reason: 'nothing is restored until the bootstrap runs',
      );

      await container.read(addressRestoreProvider.future);

      expect(container.read(districtProvider)?.id, _district.id);
      expect(container.read(addressControllerProvider).isVerified, isTrue);
    });

    test('a launch with an empty store keeps the initial state', () async {
      final container = containerWith(InMemoryAddressStore());

      await container.read(addressRestoreProvider.future);

      expect(container.read(districtProvider), isNull);
    });

    // Two taps in one frame must not race to decide what the last record is.
    test('writes land in the order they were made', () async {
      final store = InMemoryAddressStore();
      final container = containerWith(store);
      final controller = container.read(addressControllerProvider.notifier);

      controller.continueReadOnly(district: _district);
      controller.acceptVerification(district: _district, proof: _proof());
      controller.continueReadOnly();
      await pumpEventQueue();

      expect(store.current?.district, isNull);
      expect(store.current?.isVerified, isFalse);
    });
  });

  group('a store that fails', () {
    // Losing a write costs the resident a re-onboard next launch. That is not
    // worth failing the tap that caused it.
    test('does not fail the tap that caused the write', () async {
      final container = ProviderContainer(
        overrides: [
          addressStoreProvider.overrideWithValue(const _FailingAddressStore()),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: _district);
      await pumpEventQueue();

      expect(container.read(districtProvider)?.id, _district.id);
    });
  });
}

class _FailingAddressStore implements AddressStore {
  const _FailingAddressStore();

  @override
  Future<AddressState?> read() async => throw StateError('unavailable');

  @override
  Future<void> write(AddressState state) async =>
      throw StateError('unavailable');

  @override
  Future<void> clear() async => throw StateError('unavailable');
}
