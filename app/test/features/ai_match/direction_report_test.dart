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

void main() {
  group('the fixture', () {
    final report = DirectionReport.fromJson(_fixture());

    test('is marked as sample data', () {
      expect(_fixture()['_note'], contains('Sample'));
    });

    // N-2: 가나다 order, whatever order the payload used.
    test('lists candidates in 가나다 order', () {
      expect(report.stances.candidates.map((c) => c.name), [
        '가상 후보 가',
        '가상 후보 나',
        '가상 후보 다',
      ]);
      expect(report.stances.pledgeCount, 45);
    });

    test('names the field with the largest later share', () {
      expect(report.trend.leading?.label, '주거');
      expect(report.trend.fields, hasLength(4));
    });

    test('orders issues by mentions and derives their direction', () {
      final issues = report.issues.issues;
      expect(issues.map((issue) => issue.mentions), [41, 34, 30, 25]);
      expect(issues.map((issue) => issue.direction), [
        IssueDirection.rising,
        IssueDirection.steady,
        IssueDirection.falling,
        IssueDirection.rising,
      ]);
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
