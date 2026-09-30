import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule the time core exists to hold, checked structurally.
///
/// A `DateTime.now()` in a widget is how a blackout gets decided by the device
/// instead of by the law, and a `.toLocal()` is how a Korean deadline gets read
/// in the reader's timezone. Both compile, both look ordinary in review, and
/// neither shows up in a passing test suite -- so the check is on the source
/// rather than on behaviour. Same idea as the fixture-readability check in the
/// golden harness: cheap, and it catches the thing nobody would think to test.
void main() {
  /// Where consulting the ambient clock or zone is the job.
  const allowed = {
    // The time core itself: SystemClock is the one intentional reading of the
    // device clock, and it converts to KST immediately.
    'lib/src/core/time/clock.dart',
    // The verification stamp records when this device completed onboarding.
    // It is a local event, not a legal deadline.
    'lib/src/features/onboarding/presentation/onboarding_screen.dart',
    // The source badge draws '○월 ○일 기준' in the reader's own zone, which
    // is the right reading for "when was this fetched".
    'lib/src/core/provenance/source_metadata.dart',
  };

  test('nothing in lib reads the ambient clock or zone', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (allowed.contains(entity.path)) {
        continue;
      }

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('DateTime.now()') || line.contains('.toLocal()')) {
          offenders.add('${entity.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Read the clock through clockProvider and compare in KST.\n'
          'If a new file genuinely needs the device clock, add it to the '
          'allow list above with a reason.\n${offenders.join('\n')}',
    );
  });
}
