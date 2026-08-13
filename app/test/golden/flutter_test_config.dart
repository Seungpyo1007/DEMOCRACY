import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies only to `test/golden/`. `flutter_test` picks the nearest
/// `flutter_test_config.dart` up the directory tree, so the rest of the suite
/// keeps the default exact comparator.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final existing = goldenFileComparator as LocalFileComparator;
  goldenFileComparator = _AntialiasTolerantComparator(existing.basedir);
  await testMain();
}

/// Passes a comparison whose only difference is rasteriser noise.
///
/// Pinning generation to macOS is not enough on its own: images made on
/// macOS 27.0 came back from a macOS 26.5.2 runner with a 0.04% difference,
/// 141 pixels out of 390x844. Nothing had moved -- antialiasing simply lands
/// differently between OS versions.
///
/// The threshold is set well above that noise and far below any real change.
/// 0.5% of this canvas is about 1,650 pixels; a recoloured status chip or a
/// card shifted by a few points moves several times that, because every row
/// below it moves with it. So this still fails on the regressions the goldens
/// exist to catch, and stops failing on the ones nobody can fix.
///
/// Exact-match comparison was the alternative and was tried first. It makes the
/// job unmergeable the moment GitHub rolls its macOS image, which is not a
/// signal about this codebase.
class _AntialiasTolerantComparator extends LocalFileComparator {
  // LocalFileComparator takes a test file and keeps its directory, so this
  // hands back the directory it was already using.
  _AntialiasTolerantComparator(Uri basedir)
    : super(basedir.resolve('golden_comparator_anchor_test.dart'));

  static const _threshold = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= _threshold) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
