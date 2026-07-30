class SourceMetadata {
  SourceMetadata({
    required Uri sourceUrl,
    required DateTime fetchedAt,
  })  : sourceUrl = _validateSourceUrl(sourceUrl),
        fetchedAt = fetchedAt.toUtc();

  final Uri sourceUrl;
  final DateTime fetchedAt;

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

class SourcedValue<T extends num> {
  const SourcedValue({
    required this.value,
    required this.source,
  });

  final T value;
  final SourceMetadata source;
}

