import 'dart:async';
import 'dart:convert';

import 'package:democracy/src/core/auth/address_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the address session survives a cold start.
///
/// Without this the router's guard is correct and the app is still unusable:
/// the district lives in memory only, so every launch finds no district and
/// sends the resident back through onboarding -- including the ones who
/// finished residency verification. Setting a district is a one-time act in
/// the product, and it has to behave like one.
///
/// It is a contract rather than a call to [FlutterSecureStorage] because the
/// verification proof is a server-issued bearer token. Tests must never touch
/// the Keychain, and the day the token moves behind a BFF session this is the
/// single seam that changes.
abstract interface class AddressStore {
  Future<AddressState?> read();
  Future<void> write(AddressState state);
  Future<void> clear();
}

/// Keychain on iOS, EncryptedSharedPreferences on Android.
///
/// The proof token is the reason for the ceremony. A district name is not a
/// secret, but it shares a record with the token, and splitting them across two
/// stores buys nothing and adds a way for the two to disagree.
class SecureAddressStore implements AddressStore {
  const SecureAddressStore({
    // Android takes the defaults deliberately: as of flutter_secure_storage
    // 11 the AES-GCM path is the default rather than a flag, so naming it
    // would only be a way to fall behind the package's own hardening.
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        // Not `_ThisDeviceOnly`: a resident restoring to a new phone should
        // keep their district. Not `always`: the token is a credential, so it
        // stays behind the passcode when the device is locked.
        accessibility: KeychainAccessibility.first_unlock,
      ),
    ),
  });

  final FlutterSecureStorage storage;

  static const _key = 'democracy.address.v1';

  @override
  Future<AddressState?> read() async {
    final raw = await storage.read(key: _key);
    if (raw == null) {
      return null;
    }
    try {
      return addressStateFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // A record written by an older or broken build is not worth a crash on
      // launch, and it is not worth keeping either. Drop it and onboard.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AddressState state) =>
      storage.write(key: _key, value: jsonEncode(addressStateToJson(state)));

  @override
  Future<void> clear() => storage.delete(key: _key);
}

/// The store tests and goldens get, so nothing reaches the Keychain.
class InMemoryAddressStore implements AddressStore {
  InMemoryAddressStore([this._state]);

  AddressState? _state;

  /// What the last [write] left behind, for tests that assert persistence.
  AddressState? get current => _state;

  @override
  Future<AddressState?> read() async => _state;

  @override
  Future<void> write(AddressState state) async => _state = state;

  @override
  Future<void> clear() async => _state = null;
}

final addressStoreProvider = Provider<AddressStore>(
  (ref) => const SecureAddressStore(),
);

/// Serialisation lives here rather than on [AddressState] so the domain type
/// stays free of a storage format it would otherwise be pinned to.
Map<String, dynamic> addressStateToJson(AddressState state) => {
  'status': state.status.name,
  if (state.district case final district?)
    'district': {'id': district.id, 'displayName': district.displayName},
  if (state.verification case final proof?)
    'verification': {
      'opaqueToken': proof.opaqueToken,
      'verifiedAt': proof.verifiedAt.toIso8601String(),
    },
};

AddressState addressStateFromJson(Map<String, dynamic> json) {
  final districtJson = json['district'] as Map<String, dynamic>?;
  final district = districtJson == null
      ? null
      : DistrictRef(
          id: districtJson['id'] as String,
          displayName: districtJson['displayName'] as String,
        );

  final status = AddressStatus.values.firstWhere(
    (value) => value.name == json['status'],
    orElse: () => AddressStatus.unverified,
  );

  // A verified record is only restored intact. Anything short of a district
  // plus a parseable proof comes back as read-only rather than as a session
  // that claims a verification it cannot evidence -- restoring is not a way
  // to acquire a status the server never granted.
  final verificationJson = json['verification'] as Map<String, dynamic>?;
  if (status == AddressStatus.verified &&
      district != null &&
      verificationJson != null) {
    return AddressState.verified(
      district: district,
      proof: ResidencyVerificationProof(
        opaqueToken: verificationJson['opaqueToken'] as String,
        verifiedAt: DateTime.parse(verificationJson['verifiedAt'] as String),
      ),
    );
  }

  // `pending` is deliberately not restored. It means a request is in flight
  // with a server that has no memory of this process, so resuming into it
  // would leave a spinner no reply can ever end.
  return AddressState.readOnly(district: district);
}

/// Serialises writes and keeps a failed one from reaching the UI.
///
/// Mutations are synchronous and persistence is not, so writes are chained
/// rather than fired in parallel: two taps in one frame must not race to
/// decide what the last record is. A store that refuses to write costs the
/// resident a re-onboard next launch, which is not worth failing the tap that
/// caused it.
class AddressPersistence {
  AddressPersistence(this._store);

  final AddressStore _store;
  Future<void> _pending = Future<void>.value();

  Future<void> get settled => _pending;

  void save(AddressState state) {
    _pending = _pending.then((_) => _store.write(state)).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('Could not persist the address session: $error');
    });
  }
}
