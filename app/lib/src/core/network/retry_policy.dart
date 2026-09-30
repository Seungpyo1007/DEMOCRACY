import 'package:democracy/src/core/network/bff_client.dart';

/// When a failed provider is tried again, for the whole app.
///
/// Riverpod retries every failure by default, up to ten times with a growing
/// delay, and a provider being retried reads as loading. A 「준비 중」 answer
/// or a payload refused for lacking a source comes back the same every time,
/// so the reader watched a spinner for half a minute instead of the reason.
/// Only a dropped connection is worth another try, twice and quickly; every
/// screen has its own 다시 시도 for the rest.
Duration? appRetry(int retryCount, Object error) {
  if (error is SessionExpiredException) {
    return null;
  }
  if (error is BffException && error.code == 'offline' && retryCount < 2) {
    return Duration(milliseconds: 500 * (retryCount + 1));
  }
  return null;
}
