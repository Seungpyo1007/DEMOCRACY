/// An instant, read in Korea Standard Time.
///
/// Every deadline in 공직선거법 is a Korean wall-clock time. 선거일 전 6일
/// 00:00 and 투표마감시각 mean the same moment to a voter in Seoul and to one
/// reading the app from another timezone, so nothing here may consult the
/// device zone: a phone set to UTC-8 must reach the same verdict as a phone in
/// Seoul, or the blackout is a suggestion rather than a rule.
///
/// KST has been a fixed UTC+9 with no daylight saving since 1961, so the whole
/// zone is one addition. That is why this does not pull in `timezone` and its
/// IANA database -- a zone lookup would be more code and a large asset to
/// express a constant. If Korea ever adopts summer time, this file is the one
/// place that has to learn about it.
///
/// It is an extension type over a UTC [DateTime] so it costs nothing at
/// runtime while still being a type a caller cannot satisfy with a bare
/// `DateTime` they happened to have lying around.
extension type const KstInstant._(DateTime _utc) implements Object {
  /// Wraps an instant. The argument is normalised, so a local-zone [DateTime]
  /// is converted rather than reinterpreted.
  factory KstInstant.fromDateTime(DateTime instant) =>
      KstInstant._(instant.toUtc());

  /// Reads a timestamp that states its own offset.
  ///
  /// A naive timestamp is rejected rather than assumed. `2026-04-15T00:00:00`
  /// is midnight somewhere, and guessing which somewhere is how a blackout
  /// starts nine hours late.
  factory KstInstant.parse(String iso, {required String field}) {
    final DateTime parsed;
    try {
      parsed = DateTime.parse(iso);
    } on FormatException {
      throw ArgumentError.value(iso, field, 'Not a parseable timestamp.');
    }
    if (!parsed.isUtc && !_statesAnOffset(iso)) {
      throw ArgumentError.value(
        iso,
        field,
        'A timestamp with legal effect must state its offset '
        '(a trailing Z or +09:00).',
      );
    }
    return KstInstant._(parsed.toUtc());
  }

  /// Builds an instant from Korean wall-clock parts.
  factory KstInstant.seoul(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => KstInstant._(
    DateTime.utc(year, month, day, hour, minute, second).subtract(offset),
  );

  /// Korea has been UTC+9 with no daylight saving since 1961.
  static const offset = Duration(hours: 9);

  DateTime get utc => _utc;

  /// The Korean wall clock. Deliberately built by addition rather than by
  /// [DateTime.toLocal], which would answer with the device's zone.
  DateTime get wallClock => _utc.add(offset);

  /// Midnight in Seoul on the same Korean calendar day.
  KstInstant get startOfDay {
    final wall = wallClock;
    return KstInstant.seoul(wall.year, wall.month, wall.day);
  }

  KstInstant minusDays(int days) =>
      KstInstant._(_utc.subtract(Duration(days: days)));

  bool isBefore(KstInstant other) => _utc.isBefore(other._utc);
  bool isAtOrAfter(KstInstant other) => !isBefore(other);

  Duration difference(KstInstant other) => _utc.difference(other._utc);

  /// '4월 15일' -- the Korean calendar day, not the reader's.
  String get dayLabel => '${wallClock.month}월 ${wallClock.day}일';

  /// '4월 15일 18:00' -- used where a deadline has to be exact.
  String get stampLabel {
    final wall = wallClock;
    final minute = wall.minute.toString().padLeft(2, '0');
    return '$dayLabel ${wall.hour}:$minute';
  }

  String toIso8601String() => _utc.toIso8601String();

  static bool _statesAnOffset(String iso) {
    // DateTime.parse accepts a naive string and hands back a local-zone value,
    // so the only way to tell the two apart is to look at what was written.
    final timePart = iso.split('T');
    if (timePart.length < 2) {
      return false;
    }
    final time = timePart[1];
    return time.endsWith('Z') ||
        time.endsWith('z') ||
        time.contains('+') ||
        time.lastIndexOf('-') > 0;
  }
}
