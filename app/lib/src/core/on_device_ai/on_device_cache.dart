import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Validated on-device results, kept on the device and nowhere else.
///
/// Keyed by task, district, a hash of the exact input and the model version,
/// so the same pledges read by the same model come back without a second run,
/// and anything that changes -- a new pledge, a new bill, a different
/// interest, an OS update that swaps the model -- misses and runs again.
/// Only output that has already passed validation is stored; nothing here is
/// ever sent anywhere.
abstract interface class OnDeviceResultCache {
  Future<Map<String, Object?>?> read(String key);

  Future<void> write(String key, Map<String, Object?> value);
}

/// The cache key for one run.
///
/// The input is hashed rather than stored: the key says which input produced
/// the answer without keeping a second copy of it.
String onDeviceCacheKey({
  required OnDeviceTask task,
  required String districtId,
  required Object? input,
  required String modelVersion,
}) {
  final digest = sha256.convert(utf8.encode(jsonEncode(input)));
  return '${task.name}|$districtId|$digest|$modelVersion';
}

class SharedPreferencesOnDeviceResultCache implements OnDeviceResultCache {
  SharedPreferencesOnDeviceResultCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _prefix = 'ondevice_ai.';

  final SharedPreferencesAsync _preferences;

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final raw = await _preferences.getString('$_prefix$key');
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> value) =>
      _preferences.setString('$_prefix$key', jsonEncode(value));
}

class InMemoryOnDeviceResultCache implements OnDeviceResultCache {
  final entries = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Map<String, Object?> value) async =>
      entries[key] = value;
}

/// Reads the model's answer as a JSON object.
///
/// iOS's guided generation hands back exact JSON. Android's model is asked
/// for JSON in the prompt and sometimes wraps it in a code fence or a
/// sentence, so this takes the outermost `{…}`. Anything that still does not
/// parse is an output failure, not something to guess at.
Map<String, Object?> decodeModelJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const OnDeviceModelException('output', 'no JSON object');
  }
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
  } on FormatException {
    // Falls through.
  }
  throw const OnDeviceModelException('output', 'not a JSON object');
}

/// Like [decodeModelJson], but null for a snapshot that does not parse yet.
Map<String, Object?>? tryDecodeModelJson(String text) {
  try {
    return decodeModelJson(text);
  } on OnDeviceModelException {
    return null;
  }
}
