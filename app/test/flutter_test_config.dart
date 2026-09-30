import 'dart:async';

import 'package:democracy/src/design/app_motion.dart';

/// Runs before every test outside `test/golden/` (which has its own config).
///
/// The live marker and the code caret repeat in the app. Here they are held
/// still: a repeating animation never lets `pumpAndSettle` return.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppMotion.loopsEnabled = false;
  await testMain();
}
