import 'dart:convert';

import 'package:democracy/src/core/network/bff_config.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/network/response_cache.dart';
import 'package:dio/dio.dart';

/// One decoded BFF response.
class BffResponse {
  const BffResponse({
    required this.data,
    required this.servedAt,
    this.fromCache = false,
  });

  final Map<String, Object?> data;

  /// The server's clock when it answered. The seam a server-anchored clock
  /// will read; see `serverAnchoredClockIsBffWork`.
  final DateTime servedAt;

  /// True when the network failed and this is the last response kept.
  final bool fromCache;
}

/// A failure the BFF reported, or one on the way to it.
class BffException implements Exception {
  const BffException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
  });

  /// The envelope's `error.code`, or `offline` / `malformed` for failures
  /// that never produced one.
  final String code;
  final String message;
  final int? statusCode;

  /// Anything else the error carried, like `availableAt` on `too_soon`.
  final Map<String, Object?> details;

  @override
  String toString() => 'BffException($code, $statusCode): $message';
}

/// The BFF refused the signed-in person's token: it expired or was revoked.
///
/// Separate from other failures because the answer is a sheet -- sign in
/// again, the draft is kept -- not an error message.
class SessionExpiredException extends BffException {
  const SessionExpiredException()
    : super(
        code: 'unauthorized',
        message: 'The session has expired.',
        statusCode: 401,
      );
}

/// Hands the BFF client the signed-in person's access token, or null when
/// nobody is signed in and requests go out under the anon key alone.
typedef UserTokenSource = Future<String?> Function();

/// The only thing in the app that talks to the network.
///
/// Every response is `{servedAt, data}` or `{servedAt, error}`. The data is
/// handed back undecoded into domain types: each repository runs it through
/// the same `fromJson` the fixtures go through, so the provenance checks
/// apply to live data exactly as they do to samples.
class BffClient {
  BffClient({required this._dio, this._cache, this._userToken});

  factory BffClient.fromConfig(
    BffConfig config, {
    ResponseCache? cache,
    UserTokenSource? userToken,
  }) {
    return BffClient(
      cache: cache,
      userToken: userToken,
      dio: Dio(
        BaseOptions(
          baseUrl: config.baseUrl.toString(),
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'apikey': config.anonKey,
            'Authorization': 'Bearer ${config.anonKey}',
          },
          // Decoded here rather than by Dio so the cache stores exactly the
          // bytes the server sent.
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      ),
    );
  }

  final Dio _dio;
  final ResponseCache? _cache;
  final UserTokenSource? _userToken;

  /// Error codes that mean "not here yet" rather than "broken".
  static const _notAvailable = {'not_found', 'not_curated'};

  /// GETs [path]. With [cacheable], a successful body is kept and served
  /// again when the network fails.
  ///
  /// Only public records are cacheable. A request made as a signed-in person
  /// is never cached: an account answer kept on disk would outlive a sign-out.
  Future<BffResponse> get(
    String path, {
    Map<String, String>? query,
    bool cacheable = false,
  }) => _send('GET', path, query: query, cacheable: cacheable);

  Future<BffResponse> post(String path, {Map<String, Object?>? body}) =>
      _send('POST', path, body: body);

  Future<BffResponse> patch(String path, {Map<String, Object?>? body}) =>
      _send('PATCH', path, body: body);

  Future<BffResponse> delete(String path, {Map<String, String>? query}) =>
      _send('DELETE', path, query: query);

  Future<BffResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool cacheable = false,
  }) async {
    final token = await _userToken?.call();
    final signedIn = token != null;
    final useCache = cacheable && !signedIn;

    final Response<String> response;
    try {
      response = await _dio.request<String>(
        path,
        queryParameters: query,
        data: body == null ? null : json.encode(body),
        options: Options(
          method: method,
          headers: {
            if (signedIn) 'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (error) {
      final cached = useCache ? await _cache?.read(path) : null;
      if (cached != null) {
        return _decode(cached, fromCache: true);
      }
      throw BffException(
        code: 'offline',
        message: error.message ?? error.type.name,
      );
    }

    final text = response.data ?? '';
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final decoded = _decode(text);
      if (useCache) {
        await _cache?.write(path, text);
      }
      return decoded;
    }

    final error = _errorOf(text);
    final code = error?['code'];
    if (signedIn && status == 401) {
      throw const SessionExpiredException();
    }
    if (code is String && _notAvailable.contains(code)) {
      throw NotAvailableException(path);
    }
    throw BffException(
      code: code is String ? code : 'http_$status',
      message: error?['message'] is String
          ? error!['message']! as String
          : 'HTTP $status',
      statusCode: status,
      details: {...?error}
        ..removeWhere((k, _) => k == 'code' || k == 'message'),
    );
  }

  static BffResponse _decode(String body, {bool fromCache = false}) {
    final Object? envelope;
    try {
      envelope = json.decode(body);
    } on FormatException {
      throw const BffException(code: 'malformed', message: 'Body is not JSON.');
    }

    if (envelope is! Map<String, Object?>) {
      throw const BffException(code: 'malformed', message: 'No envelope.');
    }
    final data = envelope['data'];
    final servedAt = envelope['servedAt'];
    final parsedAt = servedAt is String ? DateTime.tryParse(servedAt) : null;
    if (data is! Map<String, Object?> || parsedAt == null) {
      throw const BffException(
        code: 'malformed',
        message: 'The envelope needs data and servedAt.',
      );
    }

    return BffResponse(
      data: data,
      servedAt: parsedAt.toUtc(),
      fromCache: fromCache,
    );
  }

  static Map<String, Object?>? _errorOf(String body) {
    try {
      final envelope = json.decode(body);
      if (envelope is Map && envelope['error'] is Map<String, Object?>) {
        return envelope['error'] as Map<String, Object?>;
      }
    } on FormatException {
      // Not an envelope; the status code is all there is to report.
    }
    return null;
  }
}
