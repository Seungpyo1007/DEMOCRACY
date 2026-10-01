import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves each screenshot the test takes under `build/screenshots/`.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
