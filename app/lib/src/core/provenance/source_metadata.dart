/// Raised when a payload carries an external figure without usable provenance.
///
/// This is a plain exception rather than an assertion on purpose: assertions
/// are stripped from release builds, and an unsourced figure reaching a screen
/// in production is exactly the case that has to fail.
class MissingSourceException implements Exception {
  const MissingSourceException({required this.field, required this.reason});

  final String field;
  final String reason;

  @override
  String toString() => 'MissingSourceException on "$field": $reason';
}

class SourceMetadata {
  SourceMetadata({required Uri sourceUrl, required DateTime fetchedAt})
    : sourceUrl = _validateSourceUrl(sourceUrl),
      fetchedAt = fetchedAt.toUtc();

  /// Reads provenance from a decoded payload.
  ///
  /// [field] names the figure being parsed and appears in the failure, so a
  /// rejected payload says which value was unsourced.
  factory SourceMetadata.fromJson(Object? json, {required String field}) {
    if (json is! Map<String, Object?>) {
      throw MissingSourceException(
        field: field,
        reason: 'No source object was supplied.',
      );
    }

    final rawUrl = json['sourceUrl'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      throw MissingSourceException(
        field: field,
        reason: 'sourceUrl is absent or empty.',
      );
    }

    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null) {
      throw MissingSourceException(
        field: field,
        reason: 'sourceUrl "$rawUrl" is not a URL.',
      );
    }

    final rawFetchedAt = json['fetchedAt'];
    if (rawFetchedAt is! String || rawFetchedAt.trim().isEmpty) {
      throw MissingSourceException(
        field: field,
        reason: 'fetchedAt is absent or empty.',
      );
    }

    final parsedFetchedAt = DateTime.tryParse(rawFetchedAt);
    if (parsedFetchedAt == null) {
      throw MissingSourceException(
        field: field,
        reason: 'fetchedAt "$rawFetchedAt" is not a timestamp.',
      );
    }

    try {
      return SourceMetadata(sourceUrl: parsedUrl, fetchedAt: parsedFetchedAt);
    } on ArgumentError catch (error) {
      throw MissingSourceException(
        field: field,
        reason: error.message.toString(),
      );
    }
  }

  final Uri sourceUrl;
  final DateTime fetchedAt;

  /// Publisher shown on the source badge, derived from the URL rather than
  /// stored separately so it can never disagree with the link it sits next to.
  String get publisher => sourceUrl.host.replaceFirst('www.', '');

  /// The "○월 ○일 기준" stamp the product spec requires next to cached figures.
  String get asOfLabel {
    final local = fetchedAt.toLocal();
    return '${local.month}월 ${local.day}일 기준';
  }

  static Uri _validateSourceUrl(Uri sourceUrl) {
    final isHttp = sourceUrl.scheme == 'http' || sourceUrl.scheme == 'https';
    if (!sourceUrl.isAbsolute || !isHttp || sourceUrl.host.isEmpty) {
      throw ArgumentError.value(
        sourceUrl,
        'sourceUrl',
        'A complete HTTP(S) source URL is required.',
      );
    }
    return sourceUrl;
  }
}

/// A figure that cannot exist without knowing where it came from.
///
/// Every externally sourced number in the domain is expressed as one of these,
/// so there is no way to render a bare figure that skipped the check.
class SourcedValue<T extends num> {
  const SourcedValue({required this.value, required this.source});

  /// Reads `{ "value": …, "sourceUrl": …, "fetchedAt": … }`.
  factory SourcedValue.fromJson(Object? json, {required String field}) {
    if (json is! Map<String, Object?>) {
      throw MissingSourceException(
        field: field,
        reason: 'No value object was supplied.',
      );
    }

    final rawValue = json['value'];
    if (rawValue is! T) {
      throw MissingSourceException(
        field: field,
        reason: 'value is absent or is not a $T.',
      );
    }

    return SourcedValue<T>(
      value: rawValue,
      source: SourceMetadata.fromJson(json, field: field),
    );
  }

  final T value;
  final SourceMetadata source;
}
