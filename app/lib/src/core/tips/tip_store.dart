import 'package:shared_preferences/shared_preferences.dart';

/// Every one-time introduction the app can show, by id.
abstract final class TipIds {
  /// The walkthrough after onboarding. Versioned so a rewritten tutorial can
  /// be shown again to readers who saw the old one.
  static const tutorial = 'tutorial.v1';

  /// The AI notice that opens on the first visit to the AI tab.
  static const aiDisclosure = 'ai.disclosure';

  static const all = {tutorial, aiDisclosure};
}

/// Which introductions the reader has already been through.
///
/// Kept apart from the address store: losing it costs a reader a tip they
/// have seen, which is harmless, so it lives in plain preferences rather than
/// the Keychain.
abstract interface class TipStore {
  Future<Set<String>> load();
  Future<void> markSeen(String id);

  /// Forgets every dismissal, for 도움말 다시 보기.
  Future<void> reset();
}

class SharedPreferencesTipStore implements TipStore {
  SharedPreferencesTipStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'tips.seen';

  final SharedPreferencesAsync _preferences;

  @override
  Future<Set<String>> load() async {
    return {...?await _preferences.getStringList(_key)};
  }

  @override
  Future<void> markSeen(String id) async {
    final seen = await load();
    await _preferences.setStringList(_key, [...seen, id]);
  }

  @override
  Future<void> reset() => _preferences.remove(_key);
}

class InMemoryTipStore implements TipStore {
  InMemoryTipStore([Set<String> seen = const {}]) : _seen = {...seen};

  final Set<String> _seen;

  @override
  Future<Set<String>> load() async => {..._seen};

  @override
  Future<void> markSeen(String id) async => _seen.add(id);

  @override
  Future<void> reset() async => _seen.clear();
}

/// Reports every tip as already seen and ignores a reset.
///
/// The default outside the running app, so a widget test or a golden never
/// finds a popover sitting over the thing it meant to tap or photograph. The
/// app wires the real store in `main.dart`; tip tests opt in with an
/// [InMemoryTipStore].
class DisabledTipStore implements TipStore {
  const DisabledTipStore();

  @override
  Future<Set<String>> load() async => {...TipIds.all};

  @override
  Future<void> markSeen(String id) async {}

  @override
  Future<void> reset() async {}
}
