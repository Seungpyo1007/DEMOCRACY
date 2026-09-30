import 'package:shared_preferences/shared_preferences.dart';

/// The last good response per path, kept so a dropped connection shows what
/// was last served instead of an error.
///
/// Serving it is honest without a separate "stale" banner: every figure in a
/// cached body still carries its own `fetchedAt`, and the source badge prints
/// that date. Only the district's public record is cached -- never an address
/// query or a position, which the guide says are not retained.
abstract interface class ResponseCache {
  Future<String?> read(String key);

  Future<void> write(String key, String body);
}

class SharedPreferencesResponseCache implements ResponseCache {
  SharedPreferencesResponseCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _prefix = 'bff.cache.';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString('$_prefix$key');

  @override
  Future<void> write(String key, String body) =>
      _preferences.setString('$_prefix$key', body);
}

class InMemoryResponseCache implements ResponseCache {
  final _entries = <String, String>{};

  @override
  Future<String?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, String body) async => _entries[key] = body;
}
