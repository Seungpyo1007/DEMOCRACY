import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Reads the bundled sample payloads.
///
/// Named "fixture" throughout, including in the asset paths, so that sample
/// data can never be mistaken for a live feed while reading the code or a
/// stack trace.
class FixtureLoader {
  const FixtureLoader({this.bundle});

  static const _directory = 'assets/fixtures';

  /// Left null so the ambient rootBundle is resolved at call time; tests pass
  /// their own bundle instead of reaching for the asset directory.
  final AssetBundle? bundle;

  Future<Map<String, Object?>> load(String name) async {
    final source = bundle ?? rootBundle;
    final raw = await source.loadString('$_directory/$name.json');
    final decoded = json.decode(raw);

    if (decoded is! Map<String, Object?>) {
      throw FormatException('Fixture "$name" is not a JSON object.');
    }
    return decoded;
  }
}
