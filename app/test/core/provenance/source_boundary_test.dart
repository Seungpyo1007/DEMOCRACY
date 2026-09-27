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
      expect(profile.incumbent!.stats.single.display, '92%');
    });

    test('refuses the whole payload when one figure is unsourced', () {
      expect(
        () => DistrictProfile.fromJson(districtJson(statValue: {'value': 92})),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('a vacant seat has no incumbent and keeps its source', () {
      final profile = DistrictProfile.fromJson(
        districtJson()
          ..['incumbent'] = null
          ..['vacant'] = true,
      );
      expect(profile.isVacant, isTrue);
      expect(profile.incumbent, isNull);
      expect(profile.source.publisher, isNotEmpty);
    });

    test('a payload that only lost its incumbent is still refused', () {
      expect(
        () => DistrictProfile.fromJson(districtJson()..['incumbent'] = null),
        throwsA(isA<MissingSourceException>()),
      );
      expect(
        () => DistrictProfile.fromJson(
          districtJson()
            ..['incumbent'] = null
            ..['vacant'] = true
            ..remove('source'),
        ),
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

    test('「판정 전」 parses, and an unknown status is never read as a verdict', () {
      expect(
        Pledge.fromJson(pledgeJson(status: 'notJudged')).status,
        PledgeStatus.notJudged,
      );
      expect(PledgeStatus.notJudged.display, '○ 판정 전');
      // Before 「판정 전」 existed, anything unrecognised became 미이행.
      for (final raw in ['kept', '', null, 3]) {
        expect(PledgeStatus.parse(raw), PledgeStatus.notJudged, reason: '$raw');
      }
      expect(PledgeStatus.parse('unfulfilled'), PledgeStatus.unfulfilled);
    });

    test('a 판정 전 pledge drops any judgement or evidence it was sent', () {
      final pledge = Pledge.fromJson({
        ...pledgeJson(
          status: 'notJudged',
          evidenceUrl: 'https://open.assembly.go.kr/fixture/diff',
        ),
        'judgement': {
          'steps': [
            {'actor': '누군가', 'detail': '', 'stamp': ''},
          ],
          'source': sourceJson(),
        },
      });

      expect(pledge.status.isJudged, isFalse);
      expect(pledge.evidenceUrl, isNull);
      expect(pledge.judgement, isNull);
    });

    test('a board with nothing judged has no fulfilment rate', () {
      final board = PledgeBoard.fromJson({
        'pledges': [
          {...pledgeJson(status: 'notJudged'), 'id': 'a', 'category': '교통'},
          {...pledgeJson(status: 'notJudged'), 'id': 'b', 'category': '교통'},
        ],
        'source': sourceJson(),
      });

      expect(board.hasJudgements, isFalse);
      expect(board.fulfilmentRate, isNull);
      expect(board.fulfilmentDisplay, isNull);
      expect(board.categories, isEmpty);
    });

    test('the rate is kept over judged; 판정 전 is on neither side', () {
      final board = PledgeBoard.fromJson({
        'pledges': [
          {...pledgeJson(status: 'fulfilled'), 'id': 'a', 'category': '교통'},
          {...pledgeJson(status: 'unfulfilled'), 'id': 'b', 'category': '교통'},
          {...pledgeJson(status: 'notJudged'), 'id': 'c', 'category': '교통'},
          {...pledgeJson(status: 'notJudged'), 'id': 'd', 'category': '환경'},
        ],
        'source': sourceJson(),
      });

      expect(board.judgedCount, 2);
      expect(board.fulfilmentDisplay, '50%');
      expect(board.categories.map((c) => c.category), ['교통']);
      expect(board.categories.single.total, 2);
    });

    test('an unsourced pledge is refused', () {
      expect(
        () => Pledge.fromJson({'id': 'fixture-pledge', 'title': '가상 공약'}),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });
}
