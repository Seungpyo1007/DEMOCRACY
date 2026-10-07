import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _gongboUrl =
    'https://policy.nec.go.kr/policy_pdf/20240410/PDF/PBINFO_PUB/1101/fixture.pdf';

class _BoardRepository implements PledgeRepository {
  const _BoardRepository(this.json);

  final Map<String, Object?> json;

  @override
  Future<PledgeBoard> loadBoard(String districtId) async =>
      PledgeBoard.fromJson(json);
}

Map<String, Object?> _pledge(String id, String title) => {
  'id': id,
  'title': title,
  'category': '',
  'status': 'notJudged',
  'source': {'sourceUrl': _gongboUrl, 'fetchedAt': '2026-09-27T03:00:00Z'},
};

final _board = <String, Object?>{
  'source': {'sourceUrl': _gongboUrl, 'fetchedAt': '2026-09-27T03:00:00Z'},
  'pledges': [_pledge('p1', '청년 임대주택 공급'), _pledge('p2', '전통시장 시설 현대화')],
};

typedef _Opened = ({Uri url, SourceMetadata? source, String? title});

void main() {
  Future<List<_Opened>> pumpDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <_Opened>[];
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        pledgeRepositoryProvider.overrideWithValue(_BoardRepository(_board)),
        districtRepositoryProvider.overrideWithValue(
          FakeDistrictRepository(loader: fixtureLoaderFromDisk()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(
          district: const DistrictRef(
            id: 'fixture-seoul-mapo-b',
            displayName: '서울 마포구 을',
          ),
        );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => PledgeDetailScreen(
            pledgeId: id,
            opener: (context, url, {source, title}) async =>
                opened.add((url: url, source: source, title: title)),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('names the 선거공보 the pledge came from and opens it in the app', (
    tester,
  ) async {
    final opened = await pumpDetail(tester, 'p1');

    expect(find.text('청년 임대주택 공급'), findsWidgets);
    expect(find.text('○ 판정 전'), findsOneWidget);
    expect(find.text('02 공약 출처'), findsOneWidget);
    expect(find.text('제22대 국회의원선거 선거공보'), findsOneWidget);
    expect(find.text('policy.nec.go.kr'), findsOneWidget);
    expect(find.text('9월 27일 기준'), findsOneWidget);

    final link = find.byKey(PledgeDetailKeys.sourceDocument);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: link, matching: find.text('선거공보 원문 보기')),
      findsOneWidget,
    );
    await tester.tap(link);
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.url, Uri.parse(_gongboUrl));
    expect(opened.single.title, '제22대 국회의원선거 선거공보');
    expect(opened.single.source?.publisher, 'policy.nec.go.kr');
  });

  testWidgets(
    'lists the incumbent\'s bills that share a word, as a word match',
    (tester) async {
      await pumpDetail(tester, 'p1');

      final section = find.byKey(PledgeDetailKeys.sharedWordBills);
      await tester.ensureVisible(section);
      await tester.pumpAndSettle();

      Finder inSection(Finder finder) =>
          find.descendant(of: section, matching: finder);

      expect(inSection(find.text('03 제목이 겹치는 대표 발의 법안')), findsOneWidget);
      expect(inSection(find.text('역세권 청년주택 공급 촉진법 일부개정안')), findsOneWidget);
      expect(inSection(find.textContaining('겹친 낱말 청년, 공급')), findsOneWidget);
      expect(inSection(find.textContaining('판단한 결과가 아닙니다')), findsOneWidget);
      // Shares no word with the pledge.
      expect(find.text('도시공원 보전 및 이용에 관한 법률 개정안'), findsNothing);
    },
  );

  testWidgets('leaves the bill section out when nothing shares a word', (
    tester,
  ) async {
    await pumpDetail(tester, 'p2');

    expect(find.text('제22대 국회의원선거 선거공보'), findsOneWidget);
    expect(find.byKey(PledgeDetailKeys.sharedWordBills), findsNothing);
  });

  test('tells a 선거공보 from other sources by its URL', () {
    expect(brochureTitle(Uri.parse(_gongboUrl)), '제22대 국회의원선거 선거공보');
    expect(
      brochureTitle(
        Uri.parse('https://policy.nec.go.kr/policy_pdf/20280412/x.pdf'),
      ),
      '선거공보',
    );
    expect(
      brochureTitle(Uri.parse('https://open.assembly.go.kr/fixture')),
      isNull,
    );
  });
}
