import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/network/response_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_bff.dart';

void main() {
  test('unwraps data and servedAt', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/ping': (status: 200, body: envelope({'ok': true})),
      }),
    );

    final response = await client.get('/ping');

    expect(response.data, {'ok': true});
    expect(response.servedAt, DateTime.utc(2026, 9, 24, 3));
    expect(response.fromCache, isFalse);
  });

  test('a body without an envelope is malformed, not data', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/bare': (status: 200, body: {'ok': true}),
      }),
    );

    await expectLater(
      client.get('/bare'),
      throwsA(isA<BffException>().having((e) => e.code, 'code', 'malformed')),
    );
  });

  // Not ready is not broken: the screen says 준비 중 and offers no retry.
  for (final code in ['not_found', 'not_curated']) {
    test('$code is raised as not available', () async {
      final client = fakeBffClient(
        FakeBffAdapter({'/x': (status: 404, body: errorEnvelope(code))}),
      );

      await expectLater(
        client.get('/x'),
        throwsA(isA<NotAvailableException>()),
      );
    });
  }

  test('other errors keep their code and status', () async {
    final client = fakeBffClient(
      FakeBffAdapter({'/x': (status: 502, body: errorEnvelope('upstream'))}),
    );

    await expectLater(
      client.get('/x'),
      throwsA(
        isA<BffException>()
            .having((e) => e.code, 'code', 'upstream')
            .having((e) => e.statusCode, 'status', 502),
      ),
    );
  });

  test('offline serves the last good response, marked as cached', () async {
    final cache = InMemoryResponseCache();
    final routes = <String, FakeRoute>{
      '/profile': (status: 200, body: envelope({'v': 1})),
    };
    final client = fakeBffClient(FakeBffAdapter(routes), cache: cache);

    await client.get('/profile', cacheable: true);
    routes.clear();
    final offline = await client.get('/profile', cacheable: true);

    expect(offline.data, {'v': 1});
    expect(offline.fromCache, isTrue);
  });

  test('a request not marked cacheable is never kept', () async {
    final cache = InMemoryResponseCache();
    final client = fakeBffClient(
      FakeBffAdapter({
        '/address/search': (status: 200, body: envelope({'suggestions': []})),
      }),
      cache: cache,
    );

    await client.get('/address/search', query: {'q': '마포구 성미산로'});

    expect(await cache.read('/address/search'), isNull);
  });

  test('offline with nothing kept is an offline error', () async {
    final client = fakeBffClient(FakeBffAdapter({}));

    await expectLater(
      client.get('/profile', cacheable: true),
      throwsA(isA<BffException>().having((e) => e.code, 'code', 'offline')),
    );
  });
}
