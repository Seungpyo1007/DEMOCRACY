import 'package:url_launcher/url_launcher.dart';

/// The documents a reader agrees to, published from `docs/legal/` on GitHub
/// Pages so the store listings and the app point at the same page.
abstract final class LegalLinks {
  static final _base = Uri.parse('https://seungpyo1007.github.io/DEMOCRACY/');

  static final privacy = _base.resolve('privacy/');
  static final terms = _base.resolve('terms/');
  static final accountDeletion = _base.resolve('account-deletion/');

  /// In the browser, not a web view: the reader can keep or share the page.
  static Future<void> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
