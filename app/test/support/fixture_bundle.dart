import 'dart:io';

import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:flutter/services.dart';

/// Serves the real fixture files straight off disk.
///
/// Screens should show the payload that actually ships, so this reads the same
/// JSON through the same `*.fromJson` the app uses rather than swapping in data
/// shaped to please the test.
///
/// It exists because `rootBundle` does not: asset loads go out over the test
/// binding's message channel, and only the first test in a file gets that
/// round-trip resolved by a plain `pump`. Every later test sat on a spinner and
/// `pumpAndSettle` timed out -- an ordering bug that looked like a platform
/// one, since whichever platform ran second was the one that failed. Reading
/// the file synchronously removes the round-trip and with it the ordering.
class FixtureFileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // `flutter test` runs with the package root as its working directory, so
    // the asset key is already the path.
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

/// A loader wired to [FixtureFileBundle], for injecting into the fakes.
FixtureLoader fixtureLoaderFromDisk() =>
    FixtureLoader(bundle: FixtureFileBundle());
