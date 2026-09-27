import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _fixture() =>
    json.decode(
          File(
            'assets/fixtures/ai_direction_fixture-seoul-mapo-b.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// What the BFF sends today: the trend and nothing model-derived.
Map<String, Object?> _live() => {
  'district': {'id': 'nec-24863648', 'displayName': '서울 마포구 을'},
  'trend': {
    'legislatorName': '가상 의원',
    'fromTerm': '21대',
    'toTerm': '22대',
    'billCount': 6,
    'fromCount': 3,
    'toCount': 3,
    'excludedCount': 1,
    'fields': [
      {'label': '복지·보건', 'from': 66.7, 'to': 0},
      {'label': '국토·교통', 'from': 33.3, 'to': 100},
    ],
    'summary':
        '21대에는 복지·보건 분야 법안 비중이 가장 컸고(67%), '
        '22대에는 국토·교통 분야 비중이 가장 큽니다(100%).',
    'source': {
      'sourceUrl':
          'https://open.assembly.go.kr/portal/data/service/selectAPIServicePage.do/OK7XM1000938DS17215',
      'fetchedAt': '2026-09-24T03:00:00.000Z',
    },
  },
  'stances': null,
  'issues': null,
};

void main() {
  group('the fixture', () {
    final report = DirectionReport.fromJson(_fixture());

    test('is marked as sample data', () {
      expect(_fixture()['_note'], contains('Sample'));
    });

    // N-2: 가나다 order, whatever order the payload used.
    test('lists candidates in 가나다 order', () {
      expect(report.stances!.candidates.map((c) => c.name), [
        '가상 후보 가',
        '가상 후보 나',
        '가상 후보 다',
      ]);
      expect(report.stances!.pledgeCount, 45);
    });

    test('names the field with the largest later share', () {
      expect(report.trend!.leading?.label, '복지·보건');
      expect(report.trend!.fields, hasLength(4));
      expect(report.trend!.fromCount, 13);
      expect(report.trend!.toCount, 18);
      expect(report.trend!.excludedCount, 2);
    });

    test('orders issues by mentions and derives their direction', () {
      final issues = report.issues!.issues;
      expect(issues.map((issue) => issue.mentions), [41, 34, 30, 25]);
      expect(issues.map((issue) => issue.direction), [
        IssueDirection.rising,
        IssueDirection.steady,
        IssueDirection.falling,
        IssueDirection.rising,
      ]);
    });
  });

  group('a live payload', () {
    test('parses with the trend alone', () {
      final report = DirectionReport.fromJson(_live());

      expect(report.stances, isNull);
      expect(report.issues, isNull);
      expect(report.isEmpty, isFalse);
      expect(report.trend!.legislatorName, '가상 의원');
      expect(report.trend!.leading?.label, '국토·교통');
      expect(report.generatedAt, isNull);
    });

    test('with no block at all is an empty report, not an error', () {
      final report = DirectionReport.fromJson(const {'trend': null});

      expect(report.isEmpty, isTrue);
    });

    test('keeps a term with no bills as no point, not zero', () {
      final payload = _live();
      (payload['trend']! as Map<String, Object?>)['fields'] = [
        {'label': '환경·노동', 'from': 100, 'to': null},
      ];

      final trend = DirectionReport.fromJson(payload).trend!;

      expect(trend.fields.single.from, 100);
      expect(trend.fields.single.to, isNull);
      // With no later bills, the earlier term decides which line is inked.
      expect(trend.leading?.label, '환경·노동');
    });

    test('refuses a field with no term at all', () {
      expect(
        () => FieldShare.fromJson(const {
          'label': '기타',
          'from': null,
          'to': null,
        }),
        throwsFormatException,
      );
    });

    test('refuses a count that is not one', () {
      final payload = _live();
      (payload['trend']! as Map<String, Object?>)['excludedCount'] = -1;

      expect(() => DirectionReport.fromJson(payload), throwsFormatException);
    });
  });

  group('provenance', () {
    for (final section in ['stances', 'trend', 'issues']) {
      test('refuses $section with no source', () {
        final payload = _fixture();
        (payload[section]! as Map<String, Object?>).remove('source');

        expect(
          () => DirectionReport.fromJson(payload),
          throwsA(isA<MissingSourceException>()),
        );
      });
    }

    test('refuses a source with no fetch time', () {
      final payload = _fixture();
      ((payload['trend']! as Map<String, Object?>)['source']!
              as Map<String, Object?>)
          .remove('fetchedAt');

      expect(
        () => DirectionReport.fromJson(payload),
        throwsA(isA<MissingSourceException>()),
      );
    });

    // An absent block is 준비 중; a present one without a source is still refused.
    test('refuses a live trend with no source', () {
      final payload = _live();
      (payload['trend']! as Map<String, Object?>).remove('source');

      expect(
        () => DirectionReport.fromJson(payload),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });

  group('parsing', () {
    test('clamps a position to the plot', () {
      final stance = CandidateStance.fromJson(const {
        'candidateId': 'c',
        'name': '가상 후보',
        'x': 3,
        'y': -2,
        'pledgeCount': 1,
      });
      expect(stance.x, 1);
      expect(stance.y, -1);
    });

    test('rejects an issue with a single month', () {
      expect(
        () => LocalIssue.fromJson(const {
          'label': '쟁점',
          'monthly': [3],
        }),
        throwsFormatException,
      );
    });

    // A month's wobble in a small count is not a trend.
    test('calls a small wobble steady', () {
      const issue = LocalIssue(label: '쟁점', monthly: [6, 5, 6, 6, 5, 6]);
      expect(issue.direction, IssueDirection.steady);
    });

    test('calls something from nothing rising', () {
      const issue = LocalIssue(label: '쟁점', monthly: [0, 0, 0, 1, 2, 3]);
      expect(issue.direction, IssueDirection.rising);
    });
  });
}
