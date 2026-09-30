import 'dart:convert';
import 'dart:typed_data';

import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/response_cache.dart';
import 'package:dio/dio.dart';

/// What the fake server answers for one request.
typedef FakeRoute = ({int status, Object body});

/// A BFF in memory: routes are matched on path, and every request is
/// recorded so a test can check what the client sent.
class FakeBffAdapter implements HttpClientAdapter {
  FakeBffAdapter(this.routes);

  /// Keyed by path, or by `METHOD path` when one path answers differently per
  /// method. A missing route answers as though the network is down.
  final Map<String, FakeRoute> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final route =
        routes['${options.method} ${options.path}'] ?? routes[options.path];
    if (route == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final body = route.body is String
        ? route.body as String
        : json.encode(route.body);
    return ResponseBody.fromString(
      body,
      route.status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// `{servedAt, data}` around [data].
Map<String, Object?> envelope(Object? data) => {
  'servedAt': '2026-09-24T03:00:00Z',
  'data': data,
};

Map<String, Object?> errorEnvelope(String code) => {
  'servedAt': '2026-09-24T03:00:00Z',
  'error': {'code': code, 'message': code},
};

BffClient fakeBffClient(
  FakeBffAdapter adapter, {
  ResponseCache? cache,
  UserTokenSource? userToken,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bff.test/functions/v1/bff',
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  )..httpClientAdapter = adapter;
  return BffClient(dio: dio, cache: cache, userToken: userToken);
}
