import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whether the app is in front of the person, from now on.
///
/// Emits `false` when the app is hidden or paused and `true` when it comes
/// back. `inactive` (a call banner, the app switcher starting) still counts
/// as in front: letting go of a socket for that would only reconnect it a
/// moment later. The platform listener lives only while the stream is
/// listened to.
Stream<bool> appForegroundChanges() {
  AppLifecycleListener? listener;
  late final StreamController<bool> changes;
  changes = StreamController<bool>(
    onListen: () {
      listener = AppLifecycleListener(
        onStateChange: (state) => changes.add(isForeground(state)),
      );
    },
    onCancel: () {
      listener?.dispose();
      listener = null;
    },
  );
  return changes.stream.distinct();
}

bool isForeground(AppLifecycleState state) =>
    state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
