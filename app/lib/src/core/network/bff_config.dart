/// Where the BFF lives, read from `--dart-define`.
///
/// Absent in tests, goldens and a plain `flutter run`, which is what keeps
/// those on fixtures: the real client is only wired when a build asks for it.
/// The anon key is public by design -- every secret that matters sits in the
/// server's environment -- but it still comes from the build rather than the
/// source so staging and production cannot be crossed.
class BffConfig {
  const BffConfig({required this.baseUrl, required this.anonKey});

  static const _url = String.fromEnvironment('BFF_URL');
  static const _anonKey = String.fromEnvironment('BFF_ANON_KEY');

  /// Null when this build was not given a BFF.
  static BffConfig? fromEnvironment() {
    if (_url.isEmpty) {
      return null;
    }
    return BffConfig(baseUrl: Uri.parse(_url), anonKey: _anonKey);
  }

  final Uri baseUrl;
  final String anonKey;
}
