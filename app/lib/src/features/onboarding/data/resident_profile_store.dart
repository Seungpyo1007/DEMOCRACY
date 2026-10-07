import 'dart:convert';

import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the profile survives a restart. On this device only: it is never
/// part of an account, an export to a server or a request.
abstract interface class ResidentProfileStore {
  Future<ResidentProfile?> read();
  Future<void> write(ResidentProfile profile);
}

/// Plain preferences, not the Keychain: the profile is something the reader
/// typed into chips, not a credential, and losing it costs a few taps.
class SharedPreferencesResidentProfileStore implements ResidentProfileStore {
  SharedPreferencesResidentProfileStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'democracy.profile';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ResidentProfile?> read() async {
    final raw = await _preferences.getString(key);
    if (raw == null) {
      return null;
    }
    try {
      return ResidentProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      // Written by a build that no longer exists, or cut short. Not worth a
      // failure on launch; the reader picks again.
      return null;
    }
  }

  @override
  Future<void> write(ResidentProfile profile) =>
      _preferences.setString(key, jsonEncode(profile.toJson()));
}

/// Tests, goldens, and any build without a device to keep it on.
class InMemoryResidentProfileStore implements ResidentProfileStore {
  InMemoryResidentProfileStore([this._json]);

  Map<String, Object?>? _json;

  /// What the last [write] left, as it would be stored.
  Map<String, Object?>? get stored => _json;

  @override
  Future<ResidentProfile?> read() async =>
      _json == null ? null : ResidentProfile.fromJson(_json!);

  @override
  Future<void> write(ResidentProfile profile) async =>
      _json = jsonDecode(jsonEncode(profile.toJson())) as Map<String, Object?>;
}
