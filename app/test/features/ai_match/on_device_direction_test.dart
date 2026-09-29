import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/on_device_ai/on_device_runner.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/data/on_device/issue_run.dart';
import 'package:democracy/src/features/ai_match/data/on_device/on_device_direction_source.dart';
import 'package:democracy/src/features/ai_match/data/on_device/stance_run.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_on_device_model.dart';
import '../../support/fixture_bundle.dart';

final _source = SourceMetadata(
  sourceUrl: Uri.parse('https://example.go.kr/list'),
  fetchedAt: DateTime.utc(2026, 9, 1),
);

CitedItem _item(String key, {String? month}) => CitedItem(
  key: key,
  id: 'id-$key',
  title: '제목 $key',
  kind: CitedKind.pledge,
  source: _source,
  month: month,
);

final _run = OnDeviceRun(generatedAt: DateTime.utc(2026, 9, 30), model: 'm');

void main() {
  group('stances', () {
    final batch = [_item('P1'), _item('P2'), _item('P3')];

    test('reads the named sides as -1, 0 and 1', () {
      final marks = validateStances({
        'items': [
          {'id': 'P1', 'economy': '성장', 'regulation': '자율'},
          {'id': 'P2', 'economy': '중립', 'regulation': '중립'},
          {'id': 'P3', 'economy': ' 분배 ', 'regulation': '규제'},
        ],
      }, batch);
      expect(marks.map((m) => (m.key, m.x, m.y)), [
        ('P1', -1, 1),
        ('P2', 0, 0),
        ('P3', 1, -1),
      ]);
    });

    test('drops other words, numbers, unknown pledges and repeats', () {
      final marks = validateStances({
        'items': [
          {'id': 'P1', 'economy': '진보', 'regulation': '중립'}, // not a side
          {'id': 'P2', 'economy': 1, 'regulation': 0}, // a number
          {'id': 'P3', 'economy': '분배'}, // one axis missing
          {'id': 'P9', 'economy': '분배', 'regulation': '자율'}, // not here
          {'id': 'P3', 'economy': '분배', 'regulation': '자율'},
          {'id': 'P3', 'economy': '성장', 'regulation': '규제'}, // repeat
          {'economy': '분배', 'regulation': '자율'}, // no id
        ],
      }, batch);
      expect(marks.map((m) => (m.key, m.x, m.y)), [('P3', 1, 1)]);
    });

    test('the point is the mean, and the count is what was classified', () {
      final stances = buildStances(
        memberId: 'm',
        memberName: '가상 의원',
        marks: const [
          StanceMark(key: 'P1', x: 1, y: 1),
          StanceMark(key: 'P2', x: 1, y: -1),
          StanceMark(key: 'P3', x: -1, y: 0),
          StanceMark(key: 'P4', x: 0, y: 0),
        ],
        source: _source,
        run: _run,
      )!;
      final point = stances.candidates.single;
      expect((point.x, point.y), (0.25, 0.0));
      expect(point.pledgeCount, 4);
      expect(stances.subject, MatchSubject.incumbent);
      expect(stances.axes.xLow, '성장 중심');
      expect(stances.onDevice, _run);
    });

    test('nothing classified is no point at all', () {
      expect(
        buildStances(
          memberId: 'm',
          memberName: 'n',
          marks: const [],
          source: _source,
          run: _run,
        ),
        isNull,
      );
    });
  });

  group('issues', () {
    final now = KstInstant.seoul(2026, 9, 30, 12);

    test('the window is the last six KST months, oldest first', () {
      expect(monthWindow(now), [
        '2026-04',
        '2026-05',
        '2026-06',
        '2026-07',
        '2026-08',
        '2026-09',
      ]);
      // 1 March 00:30 KST is still February in UTC; the window is Korean.
      expect(monthWindow(KstInstant.seoul(2026, 3, 1, 0, 30), months: 2), [
        '2026-02',
        '2026-03',
      ]);
    });

    test('a thread that is one of the bills is counted once, as the bill', () {
      final bill = BillDigest(
        id: 'PRC_1',
        title: '도시철도법 일부개정법률안',
        proposedOn: '2026-07-09',
        source: SourceMetadata(
          sourceUrl: Uri.parse('https://likms.assembly.go.kr/bill/PRC_1'),
          fetchedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      final items = issueItems(
        bills: [
          bill,
          BillDigest(
            id: 'PRC_OLD',
            title: '오래된 법안',
            proposedOn: '2025-12-01',
            source: bill.source,
          ),
        ],
        threads: [
          DiscussionThread(
            id: 'bill-PRC_1',
            title: bill.title,
            origin: 'bill',
            replies: 0,
            openedAt: DateTime.utc(2026, 7, 9),
            sourceUrl: bill.source.sourceUrl,
          ),
          DiscussionThread(
            id: 'judgement-1',
            title: '숲길 확장 번복 판정',
            origin: 'judgement',
            replies: 3,
            openedAt: DateTime.utc(2026, 8, 31, 16), // 9월 1일 KST
            sourceUrl: Uri.parse('https://example.go.kr/j1'),
          ),
          const DiscussionThread(
            id: 'undated',
            title: '날짜 없음',
            origin: 'judgement',
            replies: 0,
          ),
        ],
        window: monthWindow(now),
      );
      expect(items.map((i) => (i.key, i.id, i.month)), [
        ('I1', 'PRC_1', '2026-07'),
        ('I2', 'judgement-1', '2026-09'),
      ]);
    });

    test('keeps only listed labels for items in the batch', () {
      final batch = [_item('I1'), _item('I2'), _item('I3')];
      final marks = validateIssues({
        'items': [
          {'id': 'I1', 'label': '교통'},
          {'id': 'I2', 'label': '우주 개발'}, // not on the list
          {'id': 'I3', 'label': ' 주거·부동산 '},
          {'id': 'I4', 'label': '교통'}, // not in the batch
          {'id': 'I1', 'label': '환경·에너지'}, // repeat
        ],
      }, batch);
      expect(marks.map((m) => (m.key, m.label)), [
        ('I1', '교통'),
        ('I3', '주거·부동산'),
      ]);
    });

    test('counts by month, most-mentioned first, 기타 left out', () {
      final window = monthWindow(now);
      final items = [
        _item('I1', month: '2026-04'),
        _item('I2', month: '2026-09'),
        _item('I3', month: '2026-09'),
        _item('I4', month: '2026-06'),
        _item('I5', month: '2026-06'),
      ];
      final flow = buildIssueFlow(
        items: items,
        marks: const [
          IssueMark(key: 'I1', label: '교통'),
          IssueMark(key: 'I2', label: '주거·부동산'),
          IssueMark(key: 'I3', label: '주거·부동산'),
          IssueMark(key: 'I4', label: '교통'),
          IssueMark(key: 'I5', label: '기타'),
        ],
        window: window,
        source: _source,
        run: _run,
      )!;
      // A tie keeps the fixed list's order.
      expect(flow.issues.map((i) => i.label), ['주거·부동산', '교통']);
      expect(flow.issues.map((i) => i.monthly), [
        [0, 0, 0, 0, 0, 2],
        [1, 0, 1, 0, 0, 0],
      ]);
      expect(flow.basis, '대표발의 법안·토론 제목 기준 · 기기 내 AI 분류');
      expect(flow.basis, isNot(contains('민원')));
      expect(flow.basis, isNot(contains('보도')));
      expect(flow.period, '최근 6개월');
    });

    test('only 기타 is no flow', () {
      expect(
        buildIssueFlow(
          items: [_item('I1', month: '2026-09')],
          marks: const [IssueMark(key: 'I1', label: '기타')],
          window: monthWindow(now),
          source: _source,
          run: _run,
        ),
        isNull,
      );
    });
  });

  group('the direction source', () {
    const district = 'fixture-seoul-mapo-b';
    late ScriptedOnDeviceModel model;
    late InMemoryOnDeviceResultCache cache;

    OnDeviceDirectionSource source({
      MemberBillsRepository? bills,
      FakePledgeRepository? pledges,
    }) {
      final loader = fixtureLoaderFromDisk();
      return OnDeviceDirectionSource(
        runner: OnDeviceRunner(
          model: model,
          cache: cache,
          clock: FixedClock(KstInstant.seoul(2026, 7, 30, 12)),
        ),
        districts: FakeDistrictRepository(loader: loader),
        pledges: pledges ?? FakePledgeRepository(loader: loader),
        bills: bills ?? FixtureMemberBillsRepository(loader),
        community: const _NoThreads(),
      );
    }

    // Every pledge leans 분배 and 자율; every title is 주거·부동산.
    Object? answer(OnDeviceRequest request) {
      final keys = RegExp(
        r'^([PI]\d+) ',
        multiLine: true,
      ).allMatches(request.prompt).map((m) => m[1]!).toList();
      return switch (request.task) {
        OnDeviceTask.stances => {
          'items': [
            for (final key in keys)
              {'id': key, 'economy': '분배', 'regulation': '자율'},
          ],
        },
        OnDeviceTask.issues => {
          'items': [
            for (final key in keys) {'id': key, 'label': '주거·부동산'},
          ],
        },
        OnDeviceTask.match => throw StateError('not asked'),
      };
    }

    setUp(() {
      model = ScriptedOnDeviceModel(answer: answer);
      cache = InMemoryOnDeviceResultCache();
    });

    test('places every pledge and counts the bills by month', () async {
      final blocks = await source().load(district);

      expect(blocks.unavailable, isNull);
      final point = blocks.stances!.candidates.single;
      expect((point.x, point.y, point.pledgeCount), (1.0, 1.0, 24));
      // 24 pledges in batches of 6, then one batch of titles.
      expect(model.requests.map((r) => r.task), [
        ...List.filled(4, OnDeviceTask.stances),
        OnDeviceTask.issues,
      ]);

      // The fixture's bills: May and July in the Feb-Jul window, and March.
      final issue = blocks.issues!.issues.single;
      expect(issue.label, '주거·부동산');
      expect(issue.monthly, [0, 1, 0, 1, 0, 1]);
      expect(blocks.issues!.onDevice, isNotNull);
    });

    test('the second visit is served from the cache', () async {
      await source().load(district);
      await source().load(district);
      expect(model.requests, hasLength(5));
    });

    test('a device without the model gets the reason and no blocks', () async {
      model.status = const ModelUnavailable(
        ModelUnavailableReason.modelNotReady,
      );
      final blocks = await source().load(district);
      expect(blocks.unavailable, ModelUnavailableReason.modelNotReady);
      expect(blocks.stances, isNull);
      expect(blocks.issues, isNull);
      expect(model.requests, isEmpty);
    });

    test('each block fails on its own, with a note', () async {
      final blocks = await source(
        pledges: const _NoPledges(),
        bills: const NoMemberBillsRepository(),
      ).load(district);
      expect(blocks.stances, isNull);
      expect(blocks.stancesNote, contains('공약 목록'));
      expect(blocks.issues, isNull);
      expect(blocks.issuesNote, isNotNull);
    });

    test('an answer that never validates is a note, not a figure', () async {
      model.answer = (_) => {
        'items': [
          {'id': 'P1', 'economy': '많이 분배', 'regulation': '자율'},
        ],
      };
      final blocks = await source().load(district);
      expect(blocks.stances, isNull);
      expect(blocks.stancesNote, '기기 모델의 답을 검증하지 못했습니다.');
      expect(cache.entries, isEmpty);
    });
  });
}

class _NoPledges extends FakePledgeRepository {
  const _NoPledges();

  @override
  Future<Never> loadBoard(String districtId) =>
      Future.error(const NotAvailableException('pledges'));
}

class _NoThreads implements CommunityRepository {
  const _NoThreads();

  @override
  Future<List<DiscussionThread>> loadThreads(String districtId) async =>
      const [];

  @override
  Future<void> send(String districtId, String body) async {}

  @override
  Stream<Never> watchChannel(String districtId) => const Stream.empty();
}
