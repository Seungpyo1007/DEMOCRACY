import 'package:democracy/src/core/time/kst.dart';

/// The one source of "now" the app is allowed to consult.
///
/// It exists so that the two places a time decides something with legal
/// consequence -- the publication blackout and the count embargo -- read from
/// something a test can pin and a server can later anchor, rather than from an
/// ambient call scattered through widgets.
abstract interface class Clock {
  KstInstant now();
}

/// The production clock.
///
/// Note what this cannot defend against: the device clock is user-writable, so
/// setting the phone back a week is a one-tap way around a blackout. That is
/// not fixable on the client -- see [ServerAnchoredClock] -- and it is why the
/// gate this feeds is defence in depth rather than the legal guarantee. The
/// guarantee is that the server must not put embargoed figures on the wire.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  KstInstant now() => KstInstant.fromDateTime(DateTime.now());
}

/// What tests and goldens get.
///
/// Pinning the clock is what keeps a golden meaning the same thing next year
/// as it does today.
final class FixedClock implements Clock {
  const FixedClock(this._at);

  final KstInstant _at;

  @override
  KstInstant now() => _at;
}

/// Not built yet, and deliberately left as a note rather than a stub.
///
/// The honest clock anchors on a server timestamp in the response envelope and
/// advances it with a monotonic `Stopwatch`, so a resident who moves the device
/// clock changes nothing. It needs a `servedAt` field the BFF does not exist to
/// send, and a half-built version that silently falls back to the device clock
/// would be worse than none: it would read as solved.
const serverAnchoredClockIsBffWork = true;
