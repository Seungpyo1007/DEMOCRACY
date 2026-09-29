import 'dart:async';

import 'package:democracy/src/features/reviews/data/live_channel.dart';

/// A broadcast server in memory: every join is recorded, and the test says
/// when it is accepted, when it fails and what is broadcast on it.
class FakeChannelTransport implements ChannelTransport {
  final joins = <FakeChannelLink>[];

  FakeChannelLink get last => joins.last;

  /// Links not yet closed.
  Iterable<FakeChannelLink> get open => joins.where((l) => !l.closed);

  @override
  ChannelLink join(
    String topic, {
    required void Function(String event, Map<String, Object?> payload) onEvent,
    required void Function(ChannelLinkState state) onState,
  }) {
    final link = FakeChannelLink(topic, onEvent, onState);
    joins.add(link);
    return link;
  }
}

class FakeChannelLink implements ChannelLink {
  FakeChannelLink(this.topic, this._onEvent, this._onState);

  final String topic;
  final void Function(String event, Map<String, Object?> payload) _onEvent;
  final void Function(ChannelLinkState state) _onState;
  bool closed = false;

  void accept() => _onState(ChannelLinkState.joined);

  void fail() => _onState(ChannelLinkState.failed);

  void broadcast(String event, Map<String, Object?> payload) =>
      _onEvent(event, payload);

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Timers a test fires by hand, recording the delay each was set for.
class ManualTimers {
  final delays = <Duration>[];
  final _timers = <_ManualTimer>[];

  Timer call(Duration delay, void Function() run) {
    final timer = _ManualTimer(run);
    _timers.add(timer);
    delays.add(delay);
    return timer;
  }

  bool get lastCancelled => _timers.last.cancelled;

  /// Runs the most recent timer, as if its delay had passed.
  void fireLast() {
    final timer = _timers.last;
    if (!timer.cancelled) {
      timer.run();
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.run);

  final void Function() run;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}
