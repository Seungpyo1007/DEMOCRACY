import 'package:democracy/src/core/time/kst.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsing', () {
    test('accepts a timestamp that states its offset', () {
      final zulu = KstInstant.parse('2026-04-15T09:00:00Z', field: 'x');
      final seoul = KstInstant.parse('2026-04-15T18:00:00+09:00', field: 'x');

      expect(zulu.utc, seoul.utc, reason: 'the same instant, written twice');
    });

    // '2026-04-15T00:00:00' is midnight somewhere, and guessing which
    // somewhere is how a blackout starts nine hours late.
    test('refuses a naive timestamp rather than guessing a zone', () {
      expect(
        () => KstInstant.parse('2026-04-15T00:00:00', field: 'pollsClose'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('refuses something that is not a timestamp at all', () {
      expect(
        () => KstInstant.parse('선거일', field: 'pollsClose'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts a negative offset, which is still an offset', () {
      final instant = KstInstant.parse('2026-04-14T20:00:00-04:00', field: 'x');

      expect(instant.utc, DateTime.utc(2026, 4, 15));
    });
  });

  group('the Korean wall clock', () {
    // The whole point of the type. If this ever answers with the device zone,
    // a reader abroad sees poll numbers during the Korean blackout.
    test('does not move when the ambient zone does', () {
      final instant = KstInstant.parse('2026-04-15T09:00:00Z', field: 'x');

      expect(instant.wallClock, DateTime.utc(2026, 4, 15, 18));
      expect(instant.dayLabel, '4월 15일');
      expect(
        instant.wallClock.difference(instant.utc),
        KstInstant.offset,
        reason: 'built by addition, never by toLocal',
      );
    });

    // 15:00Z is the following day in Seoul. A date computed from UTC parts
    // would call this 4월 14일 and start the blackout a day late.
    test('rolls the date over at 15:00Z, not at UTC midnight', () {
      final instant = KstInstant.parse('2026-04-14T15:00:00Z', field: 'x');

      expect(instant.dayLabel, '4월 15일');
      expect(instant.startOfDay.utc, DateTime.utc(2026, 4, 14, 15));
    });

    test('startOfDay is Seoul midnight, not UTC midnight', () {
      final evening = KstInstant.seoul(2026, 4, 15, 23, 59);

      expect(evening.startOfDay.utc, DateTime.utc(2026, 4, 14, 15));
      expect(evening.startOfDay.wallClock, DateTime.utc(2026, 4, 15));
    });

    test('stampLabel pads the minute so 18:00 is not 18:0', () {
      expect(KstInstant.seoul(2026, 4, 15, 18).stampLabel, '4월 15일 18:00');
      expect(KstInstant.seoul(2026, 4, 15, 20, 5).stampLabel, '4월 15일 20:05');
    });
  });

  group('arithmetic', () {
    test('minusDays walks back whole days', () {
      final close = KstInstant.seoul(2026, 4, 15, 18);

      expect(close.minusDays(6).wallClock, DateTime.utc(2026, 4, 9, 18));
    });

    test('ordering compares instants, not wall clocks', () {
      final earlier = KstInstant.seoul(2026, 4, 15, 17, 59, 59);
      final later = KstInstant.seoul(2026, 4, 15, 18);

      expect(earlier.isBefore(later), isTrue);
      expect(later.isBefore(earlier), isFalse);
      expect(later.isAtOrAfter(later), isTrue, reason: 'the boundary counts');
    });
  });
}
