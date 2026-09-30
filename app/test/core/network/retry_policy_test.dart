import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/network/retry_policy.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an answer that will not change is not retried', () {
    expect(appRetry(0, const NotAvailableException('pledges')), isNull);
    expect(
      appRetry(0, const MissingSourceException(field: 'x', reason: 'y')),
      isNull,
    );
    expect(appRetry(0, const SessionExpiredException()), isNull);
    expect(
      appRetry(0, const BffException(code: 'internal', message: 'm')),
      isNull,
    );
  });

  test('a dropped connection is tried twice more, quickly', () {
    const offline = BffException(code: 'offline', message: 'm');
    expect(appRetry(0, offline), const Duration(milliseconds: 500));
    expect(appRetry(1, offline), const Duration(seconds: 1));
    expect(appRetry(2, offline), isNull);
  });

  test('a 준비 중 provider settles on its error instead of loading', () async {
    var calls = 0;
    final provider = FutureProvider<int>((ref) async {
      calls++;
      throw const NotAvailableException('pledges');
    });
    final container = ProviderContainer(retry: appRetry);
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(container.read(provider).hasError, isTrue);
    expect(container.read(provider).isLoading, isFalse);
    expect(calls, 1);
  });
}
