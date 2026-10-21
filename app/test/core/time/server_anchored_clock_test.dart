import 'package:democracy/src/core/time/clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stopwatch the test moves by hand.
class _Stopwatch implements Stopwatch {
  Duration _elapsed = Duration.zero;

  void advance(Duration by) => _elapsed += by;

  @override
  Duration get elapsed => _elapsed;

  @override
  void start() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<_Stopwatch> watches;
  late ServerAnchoredClock clock;

  setUp(() {
    watches = [];
    clock = ServerAnchoredClock(
      stopwatch: () {
        final w = _Stopwatch();
        watches.add(w);
        return w;
      },
    );
  });

  test('has no verified time before a response', () {
    expect(clock.isAnchored, isFalse);
    expect(clock.verifiedNow(), isNull);
  });

  test('carries server time forward on the stopwatch', () {
    clock.anchor(DateTime.utc(2028, 4, 12, 8, 59));
    watches.last.advance(const Duration(minutes: 2));

    expect(clock.verifiedNow()!.utc, DateTime.utc(2028, 4, 12, 9, 1));
  });

  test('ignores a timestamp behind the current estimate', () {
    clock.anchor(DateTime.utc(2028, 4, 12, 9));
    watches.last.advance(const Duration(minutes: 5));
    clock.anchor(DateTime.utc(2028, 4, 12, 9, 1));

    expect(watches, hasLength(1));
    expect(clock.verifiedNow()!.utc, DateTime.utc(2028, 4, 12, 9, 5));
  });

  test('moves forward to a newer timestamp', () {
    clock.anchor(DateTime.utc(2028, 4, 12, 9));
    clock.anchor(DateTime.utc(2028, 4, 12, 10));

    expect(clock.verifiedNow()!.utc, DateTime.utc(2028, 4, 12, 10));
  });
}
