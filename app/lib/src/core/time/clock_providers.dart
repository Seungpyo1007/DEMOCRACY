import 'package:democracy/src/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The seam every time-dependent rule reads through.
///
/// No screen takes a [Clock] parameter, so there is nothing for a screen to
/// forget to pass. Tests and the golden harness override this provider; the
/// harness does it internally, which is what stops a golden from being written
/// against a wall clock.
final clockProvider = Provider<Clock>((ref) => const SystemClock());
