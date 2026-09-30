import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/poll_disclosure.dart';
import 'package:flutter_test/flutter_test.dart';

/// A complete 제108조제5항 disclosure. Every test starts here and removes one
/// thing, which is the same shape `source_boundary_test` uses: push malformed
/// payloads through the real parser rather than construct the failure by hand.
Map<String, Object?> _complete({
  String? drop,
  Map<String, Object?> override = const {},
}) {
  final json = <String, Object?>{
    'client': '가상일보',
    'pollster': '한국갤럽',
    'fieldStart': '2026-07-27T10:00:00+09:00',
    'fieldEnd': '2026-07-29T18:00:00+09:00',
    'sampleSize': 1004,
    'samplingMethod': '무선 가상번호 무작위추출',
    'surveyMethod': '전화면접(무선 100%)',
    'marginOfError': 3.1,
    'confidenceLevel': 95.0,
    'responseRate': 14.2,
    'questionnaire': 'https://www.nesdc.go.kr/fixture/g/questionnaire',
    'nesdcRegistration': 'https://www.nesdc.go.kr/fixture/g',
    'source': {
      'sourceUrl': 'https://www.nesdc.go.kr/fixture/g',
      'fetchedAt': '2026-07-30T09:00:00Z',
    },
  };
  if (drop != null) {
    json.remove(drop);
  }
  return {...json, ...override};
}

PollDisclosure _parse(Map<String, Object?> json) =>
    PollDisclosure.fromJson(json, pollLabel: '한국갤럽');

void main() {
  group('a complete disclosure', () {
    test('parses every item', () {
      final disclosure = _parse(_complete());

      expect(disclosure.pollster, '한국갤럽');
      expect(disclosure.client, '가상일보');
      expect(disclosure.sampleSize, 1004);
      expect(disclosure.marginOfError, 3.1);
      expect(disclosure.confidenceLevel, 95.0);
      expect(disclosure.responseRate, 14.2);
      expect(disclosure.fieldStart.dayLabel, '7월 27일');
      expect(disclosure.fieldEnd.dayLabel, '7월 29일');
    });

    // What has to sit beside the figure. The law asks the disclosure to
    // accompany the result, so these items cannot live only behind a tap.
    test('the inline notice carries the headline items', () {
      final notice = _parse(_complete()).inlineNotice;

      expect(notice, contains('한국갤럽'));
      expect(notice, contains('표본 1004명'));
      expect(notice, contains('±3.1%p'));
      expect(notice, contains('신뢰수준 95%'));
      expect(notice, contains('응답률 14.2%'));
    });
  });

  group('each mandatory item is mandatory', () {
    const required = {
      'client': '조사의뢰자',
      'pollster': '조사기관',
      'fieldStart': '조사일시',
      'fieldEnd': '조사일시',
      'sampleSize': '표본크기',
      'samplingMethod': '피조사자 선정방법',
      'surveyMethod': '조사방법',
      'marginOfError': '표본오차',
      'confidenceLevel': '신뢰수준',
      'responseRate': '응답률',
      'questionnaire': '질문내용',
      'nesdcRegistration': '심의위 등록',
    };

    required.forEach((key, korean) {
      test('$korean missing is refused, and named', () {
        expect(
          () => _parse(_complete(drop: key)),
          throwsA(
            isA<MissingDisclosureException>()
                .having((e) => e.missing, 'missing', contains(korean))
                .having((e) => e.pollLabel, 'pollLabel', '한국갤럽'),
          ),
        );
      });
    });

    test('the provenance of the disclosure itself is required', () {
      expect(() => _parse(_complete(drop: 'source')), throwsA(anything));
    });

    // Fixing nine payloads to learn about nine fields is a worse failure than
    // one that says all nine.
    test('every omission is reported at once', () {
      final json = _complete()
        ..remove('responseRate')
        ..remove('marginOfError')
        ..remove('sampleSize');

      expect(
        () => _parse(json),
        throwsA(
          isA<MissingDisclosureException>().having(
            (e) => e.missing,
            'missing',
            containsAll(<String>['응답률', '표본오차', '표본크기']),
          ),
        ),
      );
    });

    // Both ends of 조사일시 map to one required item, so a payload missing
    // both should not be told about it twice.
    test('a repeated item is named once', () {
      final json = _complete()
        ..remove('fieldStart')
        ..remove('fieldEnd');

      expect(
        () => _parse(json),
        throwsA(
          isA<MissingDisclosureException>().having(
            (e) => e.missing.where((m) => m == '조사일시').length,
            'times 조사일시 is named',
            1,
          ),
        ),
      );
    });
  });

  group('values that are present but do not mean what they say', () {
    test('a sample size of zero is not a sample', () {
      expect(
        () => _parse(_complete(override: {'sampleSize': 0})),
        throwsA(isA<MissingDisclosureException>()),
      );
    });

    test('a response rate over 100 is not a percentage', () {
      expect(
        () => _parse(_complete(override: {'responseRate': 140.0})),
        throwsA(isA<MissingDisclosureException>()),
      );
    });

    test('a field date with no offset is refused', () {
      expect(
        () =>
            _parse(_complete(override: {'fieldStart': '2026-07-27T10:00:00'})),
        throwsA(isA<MissingDisclosureException>()),
      );
    });

    // The same rule provenance uses: a reader has to be able to open it.
    test('a relative questionnaire URL is refused', () {
      expect(
        () => _parse(_complete(override: {'questionnaire': '/fixture/q'})),
        throwsA(isA<MissingDisclosureException>()),
      );
    });

    test('a file:// registration URL is refused', () {
      expect(
        () => _parse(
          _complete(override: {'nesdcRegistration': 'file:///tmp/reg.html'}),
        ),
        throwsA(isA<MissingDisclosureException>()),
      );
    });
  });

  group('the series that carries it', () {
    test('a poll with no disclosure at all cannot be built', () {
      expect(
        () => PollSeries.fromJson(const {
          'label': '한국갤럽',
          'accredited': true,
          'points': <Object?>[],
        }),
        throwsA(isA<MissingDisclosureException>()),
      );
    });

    // The load-bearing one. 제108조제5항 does not exempt an app's own survey,
    // and a client cannot register one with the 중앙선거여론조사심의위원회 --
    // so a series the server cannot evidence does not render at all. The
    // legal outcome falls out of the type rather than out of a reviewer
    // remembering.
    test('an unaccredited poll needs the registration too', () {
      expect(
        () => PollSeries.fromJson({
          'label': '앱 내 조사',
          'accredited': false,
          'points': const <Object?>[],
          'disclosure': _complete(drop: 'nesdcRegistration'),
        }),
        throwsA(
          isA<MissingDisclosureException>().having(
            (e) => e.missing,
            'missing',
            contains('심의위 등록'),
          ),
        ),
      );
    });

    test('a poll with no label is refused before anything else', () {
      expect(
        () => PollSeries.fromJson({'disclosure': _complete()}),
        throwsA(isA<MissingDisclosureException>()),
      );
    });
  });
}
