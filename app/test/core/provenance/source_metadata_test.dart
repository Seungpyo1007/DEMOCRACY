import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SourceMetadata', () {
    test('accepts a complete HTTPS source URL', () {
      final metadata = SourceMetadata(
        sourceUrl: Uri.parse('https://example.org/source/1'),
        fetchedAt: DateTime.parse('2026-07-30T00:00:00+09:00'),
      );

      expect(metadata.sourceUrl.host, 'example.org');
      expect(metadata.fetchedAt.isUtc, isTrue);
    });

    test('rejects a relative source URL', () {
      expect(
        () => SourceMetadata(
          sourceUrl: Uri.parse('/source/1'),
          fetchedAt: DateTime.utc(2026, 7, 30),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-HTTP source URL', () {
      expect(
        () => SourceMetadata(
          sourceUrl: Uri.parse('file:///local/source.json'),
          fetchedAt: DateTime.utc(2026, 7, 30),
        ),
        throwsArgumentError,
      );
    });
  });
}
