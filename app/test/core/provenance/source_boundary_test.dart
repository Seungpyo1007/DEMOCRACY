import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule these cover is that an external figure without provenance must not
/// reach the domain at all. Parsing is the boundary that enforces it, so these
/// push malformed payloads through the real parsers rather than constructing
/// models directly.
void main() {
  Map<String, Object?> sourceJson({
    String url = 'https://open.assembly.go.kr/fixture',
    String fetchedAt = '2026-07-30T09:00:00Z',
  }) {
    return {'sourceUrl': url, 'fetchedAt': fetchedAt};
  }

  group('SourcedValue parsing', () {
    test('accepts a figure that carries its source', () {
      final value = SourcedValue<num>.fromJson({
        'value': 92,
        ...sourceJson(),
      }, field: 'attendance');

      expect(value.value, 92);
      expect(value.source.fetchedAt.isUtc, isTrue);
    });

    test('rejects a figure with no source at all', () {
      expect(
        () => SourcedValue<num>.fromJson({'value': 92}, field: 'attendance'),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('rejects a figure whose source url is blank', () {
      expect(
        () => SourcedValue<num>.fromJson({
          'value': 92,
          ...sourceJson(url: '   '),
        }, field: 'attendance'),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('rejects a relative source url', () {
      expect(
        () => SourcedValue<num>.fromJson({
          'value': 92,
          ...sourceJson(url: '/fixture/attendance'),
        }, field: 'attendance'),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('rejects a non-http scheme', () {
      expect(
        () => SourcedValue<num>.fromJson({
          'value': 92,
          ...sourceJson(url: 'file:///local/fixture.json'),
        }, field: 'attendance'),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('rejects a figure with no fetch time', () {
      expect(
        () => SourcedValue<num>.fromJson({
          'value': 92,
          'sourceUrl': 'https://open.assembly.go.kr/fixture',
        }, field: 'attendance'),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('names the offending field in the failure', () {
      expect(
        () => SourcedValue<num>.fromJson({'value': 92}, field: '출석률'),
        throwsA(
          isA<MissingSourceException>().having(
            (error) => error.field,
            'field',
            '출석률',
          ),
        ),
      );
    });
  });

  group('district payload', () {
    Map<String, Object?> districtJson({Object? statValue}) {
      return {
        'district': {'id': 'fixture-a', 'displayName': '가상 지역구'},
        'source': sourceJson(),
        'incumbent': {
          'id': 'fixture-1',
          'name': '가상 의원',
          'party': '가나당',
          'stats': [
            {
              'label': '출석률',
              'unit': '%',
              'value': statValue ?? {'value': 92, ...sourceJson()},
            },
          ],
        },
        'candidates': <Object?>[],
      };
    }

    test('parses when every figure is sourced', () {
      final profile = DistrictProfile.fromJson(districtJson());
      expect(profile.incumbent.stats.single.display, '92%');
    });

    test('refuses the whole payload when one figure is unsourced', () {
      expect(
        () => DistrictProfile.fromJson(districtJson(statValue: {'value': 92})),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });

  group('pledges', () {
    Map<String, Object?> pledgeJson({
      String status = 'inProgress',
      Object? evidenceUrl,
    }) {
      return {
        'id': 'fixture-pledge',
        'title': '가상 공약',
        'status': status,
        'source': sourceJson(),
        'evidenceUrl': ?evidenceUrl,
      };
    }

    test('carries glyph and word alongside the status, never colour alone', () {
      for (final status in PledgeStatus.values) {
        expect(status.glyph, isNotEmpty);
        expect(status.label, isNotEmpty);
        expect(status.display, contains(status.label));
      }
    });

    test('a reversal without its evidence link is refused', () {
      expect(
        () => Pledge.fromJson(pledgeJson(status: 'reversed')),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('a reversal with its evidence link parses', () {
      final pledge = Pledge.fromJson(
        pledgeJson(
          status: 'reversed',
          evidenceUrl: 'https://open.assembly.go.kr/fixture/diff',
        ),
      );

      expect(pledge.status, PledgeStatus.reversed);
      expect(pledge.evidenceUrl, isNotNull);
    });

    test('an unsourced pledge is refused', () {
      expect(
        () => Pledge.fromJson({'id': 'fixture-pledge', 'title': '가상 공약'}),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });
}
