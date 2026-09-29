import 'dart:async';
import 'dart:math' as math;

import 'package:democracy/src/features/reviews/domain/channel_event.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';

/// Where a joined topic's broadcasts come from: Supabase Realtime in a live
/// build (`RealtimeChannelTransport`), a fake in tests.
abstract interface class ChannelTransport {
  /// Joins [topic]. Broadcasts arrive through [onEvent] and the link's state
  /// through [onState] until the returned link is closed; nothing is
  /// reported for a link after it was closed.
  ChannelLink join(
    String topic, {
    required void Function(String event, Map<String, Object?> payload) onEvent,
    required void Function(ChannelLinkState state) onState,
  });
}

abstract interface class ChannelLink {
  Future<void> close();
}

enum ChannelLinkState {
  /// The server accepted the join; broadcasts flow from here on.
  joined,

  /// The join was refused or timed out, or the socket dropped. The link is
  /// of no further use; a new one has to be joined.
  failed,
}

/// Where a [LiveChannel] stands, for tests and for anyone deciding whether
/// a read is still needed after sending.
enum LiveChannelStatus {
  /// Not started, or started without a transport: read-only, as before the
  /// socket existed.
  idle,
  connecting,
  live,

  /// The last link failed; a new one is scheduled.
  retrying,

  /// The app went to the background; the link is closed until it returns.
  paused,
  closed,
}

/// 1 s, 2 s, 4 s, ... up to 30 s between attempts.
Duration channelBackoff(int attempt) =>
    Duration(seconds: math.min(30, 1 << math.min(attempt - 1, 5)));

/// One screen's view of one district channel, kept current.
///
/// It reads the channel once, then listens on the district's broadcast topic
/// and folds each event in. The socket is a convenience, never a gate: if it
/// cannot be joined the channel still shows what the read returned, and
/// [LiveChannel.isLive] tells the sender to read again after posting, which
/// is how the channel worked before it had a socket.
///
/// Every successful join re-reads the channel, so what was said while the
/// link was down (a drop, a retry, the app in the background) is not lost;
/// events that arrive while that read is in flight are applied on top of it.
class LiveChannel {
  LiveChannel({
    required this.topic,
    required this.read,
    required this.onChange,
    required this.onError,
    this.transport,
    this.foreground,
    this.mine = const {},
    this.backoff = channelBackoff,
    Timer Function(Duration, void Function())? schedule,
  }) : _schedule = schedule ?? Timer.new;

  final String topic;

  /// Reads the channel as it stands: GET /districts/{id}/community.
  final Future<List<ChatMessage>> Function() read;

  /// The list to show, oldest first, each time it changes.
  final void Function(List<ChatMessage> messages) onChange;

  /// The first read failed; the screen has nothing to show. Later reads
  /// failing only leave the list as it was.
  final void Function(Object error, StackTrace stack) onError;

  final ChannelTransport? transport;

  /// Whether the app is in the foreground; the link is held only while it is.
  final Stream<bool>? foreground;

  /// Ids this device sent, kept by the repository across screens.
  final Set<String> mine;

  final Duration Function(int attempt) backoff;
  final Timer Function(Duration, void Function()) _schedule;

  var _log = ChannelLog.empty;
  var _status = LiveChannelStatus.idle;
  var _shown = false;

  ChannelLink? _link;
  int _linkGeneration = 0;
  int _attempt = 0;
  Timer? _retry;
  StreamSubscription<bool>? _foreground;

  int _readGeneration = 0;
  List<ChannelEvent>? _sinceRead;

  LiveChannelStatus get status => _status;

  /// Whether broadcasts are arriving, so a send needs no re-read.
  bool get isLive => _status == LiveChannelStatus.live;

  List<ChatMessage> get messages => _log.messages;

  void start() {
    unawaited(refresh());
    _foreground = foreground?.listen(_onForeground);
    if (transport != null) {
      _connect();
    }
  }

  /// Folds in an event this device produced (its own send).
  void add(ChannelEvent event) => _apply(event);

  /// Reads the channel again and merges what arrived meanwhile on top.
  Future<void> refresh() async {
    final generation = ++_readGeneration;
    _sinceRead = [];
    try {
      final fetched = await read();
      if (generation != _readGeneration ||
          _status == LiveChannelStatus.closed) {
        return;
      }
      var next = ChannelLog.read(fetched);
      for (final event in _sinceRead ?? const <ChannelEvent>[]) {
        next = next.apply(event);
      }
      _sinceRead = null;
      _set(next.markMine(mine), force: !_shown);
    } on Object catch (error, stack) {
      if (generation != _readGeneration) {
        return;
      }
      _sinceRead = null;
      if (!_shown && _status != LiveChannelStatus.closed) {
        onError(error, stack);
      }
    }
  }

  Future<void> close() async {
    _status = LiveChannelStatus.closed;
    _retry?.cancel();
    await _foreground?.cancel();
    await _drop();
  }

  void _apply(ChannelEvent event) {
    if (_status == LiveChannelStatus.closed) {
      return;
    }
    _sinceRead?.add(event);
    _set(_log.apply(event).markMine(mine));
  }

  void _set(ChannelLog next, {bool force = false}) {
    if (!force && next.showsSameAs(_log)) {
      return;
    }
    _log = next;
    _shown = true;
    onChange(next.messages);
  }

  void _connect() {
    final transport = this.transport;
    if (transport == null || _status == LiveChannelStatus.closed) {
      return;
    }
    _retry?.cancel();
    _status = LiveChannelStatus.connecting;
    final generation = ++_linkGeneration;
    _link = transport.join(
      topic,
      onEvent: (event, payload) {
        if (generation != _linkGeneration) {
          return;
        }
        final parsed = ChannelEvent.fromBroadcast(event, payload);
        if (parsed != null) {
          _apply(parsed);
        }
      },
      onState: (state) {
        if (generation != _linkGeneration) {
          return;
        }
        switch (state) {
          case ChannelLinkState.joined:
            _attempt = 0;
            _status = LiveChannelStatus.live;
            unawaited(refresh());
          case ChannelLinkState.failed:
            unawaited(_drop());
            _attempt += 1;
            _status = LiveChannelStatus.retrying;
            _retry = _schedule(backoff(_attempt), _connect);
        }
      },
    );
  }

  /// Closes the current link; nothing it reports afterwards is heard.
  Future<void> _drop() async {
    _linkGeneration += 1;
    final link = _link;
    _link = null;
    await link?.close();
  }

  void _onForeground(bool visible) {
    if (_status == LiveChannelStatus.closed) {
      return;
    }
    if (!visible) {
      _retry?.cancel();
      if (transport != null) {
        _status = LiveChannelStatus.paused;
      }
      unawaited(_drop());
      return;
    }
    if (transport == null) {
      // No socket to rejoin; a read shows what was said meanwhile.
      unawaited(refresh());
    } else if (_status == LiveChannelStatus.paused) {
      _attempt = 0;
      _connect();
    }
  }
}
