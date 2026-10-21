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
/// setting the phone back a week is a one-tap way around a blackout. Live
/// builds use [ServerAnchoredClock] for that reason. Either way the client gate
/// is defence in depth; the guarantee is that the server does not put
/// embargoed figures on the wire.
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

/// Server time, carried forward on a monotonic stopwatch.
///
/// Anchors on the `servedAt` of each fresh BFF response and advances it with
/// a [Stopwatch], so moving the device clock changes nothing. Until the first
/// fresh response arrives there is no server time, and [verifiedNow] says so
/// with null rather than quietly standing in the device clock: a gate that
/// reads it then withholds instead of guessing.
///
/// Cached responses never anchor. An old timestamp would put "now" in the
/// past, and the past is where the poll blackout had not started yet.
final class ServerAnchoredClock implements Clock {
  ServerAnchoredClock({Stopwatch Function()? stopwatch})
    : _newStopwatch = stopwatch ?? Stopwatch.new;

  final Stopwatch Function() _newStopwatch;
  DateTime? _anchor;
  Stopwatch? _sinceAnchor;

  /// Takes the server's time from a fresh response. A timestamp behind the
  /// current estimate is ignored, so the clock only moves forward.
  void anchor(DateTime servedAt) {
    final at = servedAt.toUtc();
    final current = _estimate();
    if (current != null && !at.isAfter(current)) {
      return;
    }
    _anchor = at;
    _sinceAnchor = _newStopwatch()..start();
  }

  bool get isAnchored => _anchor != null;

  /// Server time now, or null before any fresh response.
  KstInstant? verifiedNow() {
    final at = _estimate();
    return at == null ? null : KstInstant.fromDateTime(at);
  }

  /// For rules without legal weight (session expiry, labels), where a device
  /// time before the first response is fine. Legal gates use [verifiedNow].
  @override
  KstInstant now() => verifiedNow() ?? KstInstant.fromDateTime(DateTime.now());

  DateTime? _estimate() {
    final anchor = _anchor;
    final elapsed = _sinceAnchor?.elapsed;
    return anchor == null || elapsed == null ? null : anchor.add(elapsed);
  }
}
