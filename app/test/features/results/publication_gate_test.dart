import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/election_schedule.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// A payload with a 6 PM close on 15 April, the shape a general election has.
Map<String, Object?> _payload({Object? schedule = _unset}) => {
  'electionName': '제23대 국회의원선거',
  if (schedule != _unset) 'electionSchedule': schedule,
  'overallCountedShare': 71,
  'live': true,
  'districts': [
    {
      'districtId': 'd1',
      'districtName': '서울 마포구 을',
      'countedShare': 71,
      'source': {
        'sourceUrl': 'https://info.nec.go.kr/fixture/count',
        'fetchedAt': '2026-04-15T09:00:00Z',
      },
      'tallies': [
        {'name': '가상 후보 가', 'party': '가나당', 'share': 48.2},
      ],
    },
  ],
  'historical': [
    {'year': 2016, 'share': 44.1},
  ],
  'polls': [
    {
      'label': '한국갤럽',
      'accredited': true,
      'points': [
        {'year': 1, 'share': 43.0},
      ],
      'disclosure': {
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
      },
    },
  ],
};

const _unset = Object();

const _schedule = {
  'electionName': '제23대 국회의원선거',
  'pollsClose': '2026-04-15T18:00:00+09:00',
  'source': {
    'sourceUrl': 'https://info.nec.go.kr/fixture/schedule',
    'fetchedAt': '2026-01-02T09:00:00Z',
  },
};

ElectionResults _gateAt(KstInstant now, {Object? schedule = _schedule}) =>
    PublicationGate.apply(
      RawElectionResults.fromJson(_payload(schedule: schedule)),
      now: now,
    );

void main() {
  group('the schedule a payload has to state', () {
    // Silence and "no election" are different answers. Deciding for a payload
    // that never addressed the question is exactly the guess that publishes
    // embargoed figures.
    test('a missing key is refused rather than read as no election', () {
      expect(
        () => RawElectionResults.fromJson(_payload()),
        throwsA(isA<MissingScheduleException>()),
      );
    });

    test('an explicit null is honoured and nothing is withheld', () {
      final results = _gateAt(
        KstInstant.seoul(2026, 4, 15, 12),
        schedule: null,
      );

      expect(results.polls, isA<Published<List<PollSeries>>>());
      expect(results.counts, isA<Published<CountView>>());
    });

    test('a schedule with no closing time is refused', () {
      expect(
        () => RawElectionResults.fromJson(
          _payload(schedule: {'electionName': '보궐선거'}),
        ),
        throwsA(isA<MissingScheduleException>()),
      );
    });

    // The closing time has legal consequences, so it carries provenance for
    // the same reason every other figure in this app does.
    test('a schedule with no source is refused', () {
      expect(
        () => RawElectionResults.fromJson(
          _payload(schedule: {'pollsClose': '2026-04-15T18:00:00+09:00'}),
        ),
        throwsA(anything),
      );
    });
  });

  group('제108조제1항 · 여론조사 공표금지', () {
    test('polls are published on the seventh day out', () {
      final results = _gateAt(KstInstant.seoul(2026, 4, 8, 23, 59, 59));

      expect(results.polls, isA<Published<List<PollSeries>>>());
    });

    // 선거일 전 6일 00:00 KST. The boundary is inclusive: the ban is on from
    // the first instant of that day, not from one second later.
    test('polls are withheld from the first instant of the sixth day out', () {
      final results = _gateAt(KstInstant.seoul(2026, 4, 9));

      final polls = results.polls;
      expect(polls, isA<Withheld<List<PollSeries>>>());
      polls as Withheld<List<PollSeries>>;
      expect(polls.article, '공직선거법 제108조제1항');
      expect(polls.until, KstInstant.seoul(2026, 4, 15, 18));
      expect(polls.notice, contains('4월 15일 18:00'));
    });

    test('polls are still withheld one second before closing', () {
      expect(
        _gateAt(KstInstant.seoul(2026, 4, 15, 17, 59, 59)).polls,
        isA<Withheld<List<PollSeries>>>(),
      );
    });

    test('polls are published again at the closing instant', () {
      expect(
        _gateAt(KstInstant.seoul(2026, 4, 15, 18)).polls,
        isA<Published<List<PollSeries>>>(),
      );
    });
  });

  group('제167조제2항 · 개표결과 공표금지', () {
    // A different window from the poll ban, and worth pinning separately: the
    // count is embargoed from any time before closing, not only from the
    // sixth day out.
    test('the count is withheld well before the poll blackout begins', () {
      final results = _gateAt(KstInstant.seoul(2026, 3, 1));

      expect(results.counts, isA<Withheld<CountView>>());
      expect(results.polls, isA<Published<List<PollSeries>>>());
    });

    test('the count is withheld one second before closing', () {
      final counts = _gateAt(KstInstant.seoul(2026, 4, 15, 17, 59, 59)).counts;

      expect(counts, isA<Withheld<CountView>>());
      expect((counts as Withheld<CountView>).article, '공직선거법 제167조제2항');
    });

    test('the count is published at the closing instant', () {
      expect(
        _gateAt(KstInstant.seoul(2026, 4, 15, 18)).counts,
        isA<Published<CountView>>(),
      );
    });

    // The headline share is a count figure. Publishing it in a header while
    // withholding the districts would comply with nothing.
    test('the header states no share while the count is withheld', () {
      final withheld = _gateAt(KstInstant.seoul(2026, 4, 15, 12));
      final published = _gateAt(KstInstant.seoul(2026, 4, 15, 20));

      expect(withheld.header, '제23대 국회의원선거');
      expect(withheld.header, isNot(contains('개표율')));
      expect(published.header, contains('개표율'));
    });
  });

  // The regression this whole feature turns on. A reader whose device is set
  // to Los Angeles must get the Seoul answer.
  group('the device timezone changes nothing', () {
    test('an instant written in UTC-8 gets the same verdict', () {
      // 2026-04-09 00:00 KST is 2026-04-08 07:00 in UTC-8. Both name the same
      // instant, the first of the Korean blackout.
      final seoul = KstInstant.seoul(2026, 4, 9);
      final losAngeles = KstInstant.parse(
        '2026-04-08T07:00:00-08:00',
        field: 'x',
      );

      expect(losAngeles.utc, seoul.utc);
      expect(_gateAt(losAngeles).polls, isA<Withheld<List<PollSeries>>>());
    });

    test('the Korean calendar day is what the boundary is computed from', () {
      // 2026-04-08 23:00 in UTC-8 is 2026-04-09 16:00 in Seoul -- inside the
      // blackout, even though the reader's own calendar still says the 8th.
      final instant = KstInstant.parse('2026-04-08T23:00:00-08:00', field: 'x');

      expect(instant.dayLabel, '4월 9일');
      expect(_gateAt(instant).polls, isA<Withheld<List<PollSeries>>>());
    });
  });

  group('역대 결과 is not restricted', () {
    // Withholding a past election's published outcome would be the app
    // inventing a rule, which is its own kind of distortion.
    test('history survives both embargoes', () {
      final results = _gateAt(KstInstant.seoul(2026, 4, 15, 12));

      expect(results.counts, isA<Withheld<CountView>>());
      expect(results.polls, isA<Withheld<List<PollSeries>>>());
      expect(results.historical, hasLength(1));
    });
  });

  group('the next boundary a stream has to wake up for', () {
    ElectionSchedule schedule() =>
        ElectionSchedule.read({'electionSchedule': _schedule})!;

    test('is the blackout start while both are ahead', () {
      expect(
        PublicationGate.nextBoundary(
          schedule(),
          now: KstInstant.seoul(2026, 4, 1),
        ),
        KstInstant.seoul(2026, 4, 9),
      );
    });

    test('is the closing time once the blackout has begun', () {
      expect(
        PublicationGate.nextBoundary(
          schedule(),
          now: KstInstant.seoul(2026, 4, 10),
        ),
        KstInstant.seoul(2026, 4, 15, 18),
      );
    });

    // Nothing to wait for means no timer is armed, which is what keeps the
    // goldens free of a pending animation.
    test('is null once the election is over', () {
      expect(
        PublicationGate.nextBoundary(
          schedule(),
          now: KstInstant.seoul(2026, 4, 16),
        ),
        isNull,
      );
    });

    test('is null when no election is scheduled', () {
      expect(
        PublicationGate.nextBoundary(null, now: KstInstant.seoul(2026, 4, 1)),
        isNull,
      );
    });
  });
}
