import 'dart:convert';

import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves whatever the test hands it, including things that are not payloads.
class _StubBundle extends CachingAssetBundle {
  _StubBundle(this.contents);

  final Map<String, String> contents;

  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final body = contents[key];
    if (body == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(body)));
  }
}

void main() {
  test('reads a fixture by name from the fixtures directory', () async {
    final bundle = _StubBundle({'assets/fixtures/sample.json': '{"value": 1}'});

    final payload = await FixtureLoader(bundle: bundle).load('sample');

    expect(payload, {'value': 1});
    expect(
      bundle.loaded,
      ['assets/fixtures/sample.json'],
      reason: 'the name is a key, not a path -- callers pass neither',
    );
  });

  // A fixture that is valid JSON but not an object would otherwise reach a
  // fromJson expecting a map and fail somewhere further from the cause.
  test('refuses a payload that is not an object', () async {
    final bundle = _StubBundle({'assets/fixtures/list.json': '[1, 2, 3]'});

    expect(
      () => FixtureLoader(bundle: bundle).load('list'),
      throwsA(isA<FormatException>()),
    );
  });

  test('lets malformed JSON surface as itself', () async {
    final bundle = _StubBundle({'assets/fixtures/broken.json': '{oops'});

    expect(
      () => FixtureLoader(bundle: bundle).load('broken'),
      throwsA(isA<FormatException>()),
    );
  });

  // A district with no bundled payload is a real case, so it has to fail
  // loudly rather than resolve to an empty map that renders as a blank screen.
  test('lets a missing fixture surface as itself', () async {
    final bundle = _StubBundle({});

    expect(
      () => FixtureLoader(bundle: bundle).load('absent'),
      throwsA(isA<FlutterError>()),
    );
  });
}
