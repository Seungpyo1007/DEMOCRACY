import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/on_device_ai/on_device_runner.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/data/on_device/match_run.dart';
import 'package:democracy/src/features/ai_match/data/on_device/on_device_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_on_device_model.dart';
import '../../support/fixture_bundle.dart';

SourceMetadata _source(String path) => SourceMetadata(
  sourceUrl: Uri.parse('https://example.go.kr/$path'),
  fetchedAt: DateTime.utc(2026, 9, 1),
);

MatchInput _input({List<String> interests = const ['부동산', '세금']}) => MatchInput(
  memberId: 'assembly-1',
  memberName: '가상 의원',
  party: const PartyRef(name: '무소속'),
  interests: interests,
  context: const ['자영업'],
  billMonths: 6,
  pledges: [
    CitedItem(
      key: 'P1',
      id: 'pledge-a',
      title: '청년 임대주택 공급',
      category: '주거',
      kind: CitedKind.pledge,
      source: _source('pledge-a'),
    ),
    CitedItem(
      key: 'P2',
      id: 'pledge-b',
      title: '소상공인 세제 지원',
      kind: CitedKind.pledge,
      source: _source('pledge-b'),
    ),
  ],
  bills: [
    CitedItem(
      key: 'B1',
      id: 'bill-a',
      title: '주택임대차보호법 일부개정법률안',
      kind: CitedKind.bill,
      source: _source('bill-a'),
      month: '2026-07',
    ),
  ],
);

Map<String, Object?> _axis(
  String label,
  Object? score,
  List<Object?> reasons,
) => {'label': label, 'score': score, 'reasons': reasons};

Map<String, Object?> _reason(String id, [String text = '관련 있음']) => {
  'id': id,
  'text': text,
};

void main() {
  group('validating the model answer', () {
    test('keeps reasons whose citation is in the input', () {
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 80, [_reason('P1'), _reason('B1')]),
          _axis('세금', 60, [_reason('P2')]),
        ],
      }, _input());

      expect(verified.axes.map((a) => (a.label, a.score)), [
        ('부동산', 80),
        ('세금', 60),
      ]);
      expect(verified.axes.first.reasons.map((r) => r.key), ['P1', 'B1']);
      expect(verified.droppedReasons, 0);
    });

    test('drops a reason that cites something the reader was never shown', () {
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 70, [
            _reason('P9'), // not in the input
            _reason('B7'), // not in the input
            _reason('bill-a'), // the real id, not a key: not shown as such
            _reason('P1', '  '), // says nothing
            _reason('p1', '임대주택 공급 공약'), // normalised to P1
          ]),
        ],
      }, _input());

      final axis = verified.axes.single;
      expect(axis.reasons.map((r) => (r.key, r.text)), [('P1', '임대주택 공급 공약')]);
      expect(verified.droppedReasons, 4);
    });

    test('an interest with no verified reason scores 0, whatever was said', () {
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 90, [_reason('P404')]),
          _axis('세금', 40, [_reason('P2')]),
        ],
      }, _input());

      final estate = verified.axes.firstWhere((a) => a.label == '부동산');
      expect(estate.score, 0);
      expect(estate.modelScore, 90);
    });

    test('an off-scale score rejects the axis rather than being clamped', () {
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 140, [_reason('P1')]),
          _axis('세금', 55, [_reason('P2')]),
        ],
      }, _input());
      expect(verified.axes.map((a) => a.label), ['세금']);
      expect(verified.rejectedAxes, 1);
    });

    test('a score that is not a number rejects the axis', () {
      for (final bad in [-1, 100.5, '80', null, double.nan, double.infinity]) {
        final verified = validateMatch({
          'axes': [
            _axis('부동산', bad, [_reason('P1')]),
            _axis('세금', 55, [_reason('P2')]),
          ],
        }, _input());
        expect(verified.axes.map((a) => a.label), ['세금'], reason: '$bad');
      }
    });

    test('an interest the reader did not pick, or a repeat, is rejected', () {
      final verified = validateMatch({
        'axes': [
          _axis('교육', 90, [_reason('P1')]),
          _axis('세금', 50, [_reason('P2')]),
          _axis('세금', 99, [_reason('P1')]),
        ],
      }, _input());
      expect(verified.axes.map((a) => (a.label, a.score)), [('세금', 50)]);
      expect(verified.rejectedAxes, 2);
    });

    test('keeps at most two reasons per interest, and no repeats', () {
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 70, [
            _reason('P1'),
            _reason('P1', '또'),
            _reason('B1'),
            _reason('P2'),
          ]),
        ],
      }, _input());
      expect(verified.axes.single.reasons.map((r) => r.key), ['P1', 'B1']);
    });

    test('answers in the reader\'s order, not the model\'s', () {
      final verified = validateMatch({
        'axes': [
          _axis('세금', 10, [_reason('P2')]),
          _axis('부동산', 20, [_reason('P1')]),
        ],
      }, _input());
      expect(verified.axes.map((a) => a.label), ['부동산', '세금']);
    });

    test('nothing usable is an output failure', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'axes': 'none'},
        {'axes': []},
        {
          'axes': [
            _axis('교육', 50, [_reason('P1')]),
          ],
        },
      ]) {
        expect(
          () => validateMatch(json, _input()),
          throwsA(
            isA<OnDeviceModelException>().having(
              (e) => e.code,
              'code',
              'output',
            ),
          ),
          reason: '$json',
        );
      }
    });

    test('a partial answer shows only settled, verified reasons', () {
      final partial = {
        'axes': [
          _axis('부동산', 70, [
            _reason('P1'),
            _reason('P99'),
            _reason('B1', '주택임'),
          ]),
        ],
      };
      // The last reason may still be being written: held back.
      expect(verifiedSoFar(partial, _input()).map((r) => r.key), ['P1']);
      expect(
        verifiedSoFar(partial, _input(), complete: true).map((r) => r.key),
        ['P1', 'B1'],
      );
    });
  });

  group('the report', () {
    test('is the member, the mean of the axes, and sourced reasons', () {
      final input = _input();
      final verified = validateMatch({
        'axes': [
          _axis('부동산', 80, [_reason('B1', '임대차 법안')]),
          _axis('세금', 41, [_reason('P2')]),
        ],
      }, input);
      final report = buildMatchReport(
        input: input,
        verified: verified,
        run: OnDeviceRun(generatedAt: DateTime.utc(2026, 9, 30), model: 'm'),
      );

      expect(report.subject, MatchSubject.incumbent);
      expect(report.matches, hasLength(1));
      final match = report.matches.single;
      expect(match.name, '가상 의원');
      expect(match.score, 60.5);
      expect(match.axes.map((a) => a.score), [80, 41]);
      expect(match.reasons.first.source.sourceUrl.path, '/bill-a');
      expect(match.reasons.first.cites, '법안 「주택임대차보호법 일부개정법률안」');
      expect(match.reasons.first.axis, '부동산');
      expect(report.comparedPledges, 2);
      expect(report.comparedBills, 1);
      expect(report.onDevice?.model, 'm');
      expect(report.weights['model'], 'm');
    });
  });

  group('the repository', () {
    const district = 'fixture-seoul-mapo-b';
    late ScriptedOnDeviceModel model;
    late InMemoryOnDeviceResultCache cache;

    OnDeviceMatchRepository repository({ScriptedOnDeviceModel? using}) {
      final loader = fixtureLoaderFromDisk();
      return OnDeviceMatchRepository(
        runner: OnDeviceRunner(
          model: using ?? model,
          cache: cache,
          clock: FixedClock(KstInstant.seoul(2026, 9, 30, 12)),
        ),
        districts: FakeDistrictRepository(loader: loader),
        pledges: FakePledgeRepository(loader: loader),
        bills: FixtureMemberBillsRepository(loader),
      );
    }

    // The reader picked 세금 and 청년; the model answers citing a real
    // pledge, a real bill, and one that does not exist.
    Object? answer(OnDeviceRequest request) => {
      'axes': [
        _axis('세금', 70, [_reason('P2', '세제 관련 공약'), _reason('P99', '없는 공약')]),
        _axis('청년', 30, [_reason('B1', '임대차 법안')]),
      ],
    };

    const query = MatchQuery(interests: ['세금', '청년'], context: ['자영업']);

    setUp(() {
      model = ScriptedOnDeviceModel(answer: answer);
      cache = InMemoryOnDeviceResultCache();
    });

    test('runs on the device and drops the made-up citation', () async {
      final report = await repository().loadReport(district, query: query);
      final match = report.matches.single;

      expect(match.candidateId, 'fixture-incumbent-1');
      expect(match.reasons.map((r) => r.text), ['세제 관련 공약', '임대차 법안']);
      expect(report.weights['droppedReasons'], 1);
      expect(report.generatedAt, KstInstant.seoul(2026, 9, 30, 12).utc);
      expect(model.requests.single.task, OnDeviceTask.match);
      expect(model.requests.single.prompt, contains('P1 '));
      expect(model.requests.single.prompt, contains('B1 주택임대차보호법'));
    });

    test('serves the same input from the cache without a second run', () async {
      await repository().loadReport(district, query: query);
      final again = await repository().loadReport(district, query: query);
      expect(model.requests, hasLength(1));
      expect(again.matches.single.reasons, hasLength(2));
      expect(cache.entries, hasLength(1));
    });

    test('runs again when the interests or the model change', () async {
      await repository().loadReport(district, query: query);
      await repository().loadReport(
        district,
        query: const MatchQuery(interests: ['세금']),
      );
      expect(model.requests, hasLength(2));

      model.status = const ModelAvailable('test-model-2');
      await repository().loadReport(district, query: query);
      expect(model.requests, hasLength(3));
    });

    test('an answer that fails validation is not cached', () async {
      model.answer = (_) => {
        'axes': [
          _axis('세금', 500, [_reason('P1')]),
        ],
      };
      await expectLater(
        repository().loadReport(district, query: query),
        throwsA(isA<OnDeviceModelException>()),
      );
      expect(cache.entries, isEmpty);
    });

    test(
      'a device that cannot run the model says why, and runs nothing',
      () async {
        model.status = const ModelUnavailable(
          ModelUnavailableReason.appleIntelligenceNotEnabled,
        );
        await expectLater(
          repository().loadReport(district, query: query),
          throwsA(
            isA<OnDeviceUnavailableException>().having(
              (e) => e.reason,
              'reason',
              ModelUnavailableReason.appleIntelligenceNotEnabled,
            ),
          ),
        );
        expect(model.requests, isEmpty);
      },
    );

    test('no interest picked asks for one instead of inventing axes', () async {
      await expectLater(
        repository().loadReport(district),
        throwsA(isA<MatchNeedsInterestsException>()),
      );
      expect(model.requests, isEmpty);
    });

    test('reports verified reasons while the run is going', () async {
      final repo = repository();
      final seen = <MatchProgress>[];
      final sub = repo.progress.listen(seen.add);
      await repo.loadReport(district, query: query);
      await sub.cancel();

      expect(seen.first.characters, 0);
      expect(seen.last.characters, greaterThan(0));
      // Never a reason citing P99, at any point.
      for (final progress in seen) {
        expect(progress.verified.map((r) => r.text), isNot(contains('없는 공약')));
      }
    });

    test('streams the verified reasons once the run is done', () async {
      final repo = repository();
      final report = await repo.loadReport(district, query: query);
      final streamed = await repo
          .streamReasoning(district, report.matches.single.candidateId)
          .toList();
      expect(streamed, ['세제 관련 공약 임대차 법안']);
    });

    test('with nothing on record there is nothing to compare', () async {
      final loader = fixtureLoaderFromDisk();
      final repo = OnDeviceMatchRepository(
        runner: OnDeviceRunner(
          model: model,
          cache: cache,
          clock: FixedClock(KstInstant.seoul(2026, 9, 30)),
        ),
        districts: FakeDistrictRepository(loader: loader),
        pledges: const _NoPledges(),
        bills: const NoMemberBillsRepository(),
      );
      await expectLater(
        repo.loadReport(district, query: query),
        throwsA(isA<NotAvailableException>()),
      );
    });
  });
}

class _NoPledges extends FakePledgeRepository {
  const _NoPledges();

  @override
  Future<Never> loadBoard(String districtId) =>
      Future.error(const NotAvailableException('pledges'));
}
