import 'dart:async';

import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/time/clock.dart';

/// Runs requests against the device's model one at a time.
///
/// On-device models serve one request at a time (Android answers `BUSY` to a
/// second), and the match and the direction view can both be open, so every
/// run here waits for the one before it. The runner also holds the cache and
/// the clock the results are stamped with.
class OnDeviceRunner {
  OnDeviceRunner({
    required this.model,
    required this.cache,
    required this.clock,
  });

  final OnDeviceModel model;
  final OnDeviceResultCache cache;
  final Clock clock;

  Future<void> _tail = Future.value();

  /// The model's version, or [OnDeviceUnavailableException] with the reason
  /// it cannot run here.
  Future<String> requireModel() async {
    return switch (await model.availability()) {
      ModelAvailable(:final modelVersion) => modelVersion,
      ModelUnavailable(:final reason) => throw OnDeviceUnavailableException(
        reason,
      ),
    };
  }

  /// When a result produced now should say it was produced.
  DateTime now() => clock.now().utc;

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    // The next run waits for this one to settle, whether it failed or not.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// One request, answered as a JSON string.
  Future<String> generate(OnDeviceRequest request) =>
      _serial(() => model.generate(request));

  /// One request, streamed: [onSnapshot] sees each growing snapshot, and the
  /// future completes with the last one.
  Future<String> generateStreaming(
    OnDeviceRequest request,
    void Function(String snapshot) onSnapshot,
  ) {
    return _serial(() async {
      var last = '';
      await for (final snapshot in model.stream(request)) {
        last = snapshot;
        onSnapshot(snapshot);
      }
      if (last.trim().isEmpty) {
        throw const OnDeviceModelException('output', 'empty stream');
      }
      return last;
    });
  }
}
