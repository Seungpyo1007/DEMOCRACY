import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/fake_address_repositories.dart';
import 'package:democracy/src/features/onboarding/presentation/address_search_screen.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(id: 'fixture-a', displayName: '가상 지역구');

const _source = {
  'sourceUrl': 'https://open.assembly.go.kr/fixture',
  'fetchedAt': '2026-07-30T09:00:00Z',
};

class FakeProfileRepository implements DistrictRepository {
  const FakeProfileRepository({
    this.failure,
    this.withRecord = true,
    this.vacant = false,
  });

  final Object? failure;

  /// The member list names nobody for the district.
  final bool vacant;

  /// A district whose activity feed is not wired yet still has to render.
  final bool withRecord;

  @override
  Future<DistrictProfile> loadProfile(String districtId) async {
    if (failure != null) {
      throw failure!;
    }
    return DistrictProfile.fromJson({
      'district': {'id': districtId, 'displayName': _district.displayName},
      'source': _source,
      if (vacant) 'vacant': true,
      if (!vacant)
        'incumbent': {
          'id': 'fixture-incumbent',
          'name': '가상 의원',
          'party': '가나당',
          'stats': [
            {
              'label': '출석률',
              'unit': '%',
              'value': {'value': 92, ..._source},
            },
          ],
          if (withRecord)
            'record': {
              'bills': {
                'source': _source,
                'items': [
                  {
                    'id': 'fixture-bill-1',
                    'title': '가상 법안',
                    'stage': '소위 심사',
                    'stamp': '6월 3일',
                  },
                ],
              },
              'attendance': {
                'unit': '%',
                'source': _source,
                'points': [
                  {'label': '6월', 'value': 92},
                  {'label': '7월', 'value': 95},
                ],
              },
              'votes': {
                'unit': '%',
                'source': _source,
                'points': [
                  {'label': '6월', 'value': 87},
                  {'label': '7월', 'value': 88},
                ],
              },
            },
        },
      'candidates': [
        {
          'id': 'fixture-c3',
          'name': '다후보',
          'party': '다라당',
          'stats': <Object?>[],
        },
        {
          'id': 'fixture-c1',
          'name': '가후보',
          'party': '나다당',
          'stats': <Object?>[],
        },
      ],
    });
  }
}

class FakeBoardRepository implements PledgeRepository {
  const FakeBoardRepository();

  @override
  Future<PledgeBoard> loadBoard(String districtId) async {
    return PledgeBoard.fromJson({
      'source': _source,
      'pledges': [
        {
          'id': 'fixture-pledge-1',
          'title': '가상 공약',
          'status': 'inProgress',
          'source': _source,
        },
      ],
    });
  }
}

void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    DistrictRepository profileRepository = const FakeProfileRepository(),
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    // Tall enough that the candidate section, below the incumbent's record,
    // is laid out rather than left unbuilt past the end of the viewport.
    tester.view
      ..physicalSize = const Size(390, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        districtRepositoryProvider.overrideWithValue(profileRepository),
        pledgeRepositoryProvider.overrideWithValue(const FakeBoardRepository()),
        addressSearchRepositoryProvider.overrideWithValue(
          FakeAddressSearchRepository(loader: fixtureLoaderFromDisk()),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A real router: the district switch pushes the address search page.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const DistrictHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.addressSearch,
          builder: (context, state) => const AddressSearchScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(platform),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('shows the district and its read-only state', (tester) async {
    await pumpHome(tester);

    // Material's large top app bar sets the title twice -- expanded and
    // collapsed -- so the name is the bar's title, not a hand-drawn header.
    expect(
      find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.text('가상 지역구'),
      ),
      findsWidgets,
    );
    expect(find.text('내 지역구'), findsOneWidget);
    expect(find.text('읽기 전용'), findsOneWidget);
  });

  testWidgets('a vacant seat says so, with the list it was read from', (
    tester,
  ) async {
    await pumpHome(
      tester,
      profileRepository: const FakeProfileRepository(vacant: true),
    );

    expect(find.text('현재 공석'), findsOneWidget);
    expect(find.text('가상 의원'), findsNothing);
    // No record tabs for a member who is not there; candidates still show.
    expect(find.text('법안'), findsNothing);
    expect(find.text('가후보'), findsOneWidget);
    expect(find.byType(SourceBadge), findsWidgets);
  });

  testWidgets('the district switch is a toolbar action', (tester) async {
    await pumpHome(tester);

    final action = find.widgetWithIcon(IconButton, AppIcons.search.material);
    expect(action, findsOneWidget);
    expect(tester.widget<IconButton>(action).tooltip, '지역구 변경');

    await tester.tap(action);
    await tester.pumpAndSettle();

    // The existing district-change flow, now a page of its own.
    expect(find.byType(AddressSearchScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a district picked on the search page replaces the old one, '
      'read-only', (tester) async {
    final container = await pumpHome(tester);

    await tester.tap(find.widgetWithIcon(IconButton, AppIcons.search.material));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AddressSearchScreen),
        matching: find.byType(EditableText),
      ),
      '월드컵북로',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('서울 마포구 월드컵북로 400'));
    await tester.pumpAndSettle();

    expect(find.byType(AddressSearchScreen), findsNothing);
    final address = container.read(addressControllerProvider);
    expect(address.district?.id, 'fixture-seoul-mapo-b');
    expect(address.status, AddressStatus.unverified);
  });

  testWidgets('backing out of the search page keeps the district', (
    tester,
  ) async {
    final container = await pumpHome(tester);

    await tester.tap(find.widgetWithIcon(IconButton, AppIcons.search.material));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    expect(find.byType(AddressSearchScreen), findsNothing);
    expect(container.read(addressControllerProvider).district, _district);
  });

  testWidgets('pulling the page down refreshes it', (tester) async {
    await pumpHome(tester);

    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('the sort rule is a menu with 가나다순 checked', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('정렬 가나다순'));
    await tester.pumpAndSettle();

    final item = find.widgetWithText(MenuItemButton, '가나다순');
    expect(item, findsOneWidget);
    expect(
      find.descendant(of: item, matching: find.byIcon(Icons.check)),
      findsOneWidget,
      reason: 'the ordering in force is the checked one',
    );
  });

  testWidgets('every figure is shown with its source and as-of date', (
    tester,
  ) async {
    await pumpHome(tester);

    // Figures carry a smaller unit, so they render as rich text.
    expect(find.text('92%', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('출처 open.assembly.go.kr'),
      findsWidgets,
      reason: 'A figure must never appear without its attribution.',
    );
    expect(find.textContaining('기준'), findsWidgets);
  });

  testWidgets('candidates are listed in name order with the rule on screen', (
    tester,
  ) async {
    await pumpHome(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where((text) => text.endsWith('후보'))
        .toList();

    expect(names.indexOf('가후보'), lessThan(names.indexOf('다후보')));
    expect(find.textContaining('가나다순'), findsOneWidget);
    expect(find.textContaining('출마 후보 2명', findRichText: true), findsOneWidget);
  });

  // N-2: no challenger gets a bigger card than another.
  testWidgets('every candidate card is the same size', (tester) async {
    await pumpHome(tester);

    Size cardOf(String name) => tester.getSize(
      find.ancestor(of: find.text(name), matching: find.byType(RevealIn)).first,
    );

    expect(cardOf('가후보'), cardOf('다후보'));
  });

  testWidgets('renders the iOS layout with the same content', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester, platform: TargetPlatform.iOS);

    // No bar on iOS: the large title sits on the page, once.
    expect(find.text('가상 지역구'), findsOneWidget);
    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.text('읽기 전용'), findsOneWidget);
    expect(find.text('92%', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('지역구 변경')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a pledge status is never colour alone', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining(PledgeStatus.inProgress.label), findsOneWidget);
    expect(find.textContaining(PledgeStatus.inProgress.glyph), findsOneWidget);
  });

  testWidgets('an unsourced payload is reported as such, not rendered', (
    tester,
  ) async {
    await pumpHome(
      tester,
      profileRepository: const FakeProfileRepository(
        failure: MissingSourceException(
          field: '출석률',
          reason: 'sourceUrl is absent or empty.',
        ),
      ),
    );

    // The profile feeds both the incumbent and the candidate sections, so a
    // rejected payload surfaces in each of them.
    expect(find.textContaining('출처가 확인되지 않아'), findsWidgets);
    expect(find.text('92%', findRichText: true), findsNothing);
  });

  group('the record tabs', () {
    testWidgets('open the bill, attendance and vote panes', (tester) async {
      await pumpHome(tester);

      for (final tab in ['법안', '출석', '표결']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      expect(find.text('월별 표결 참여율'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      // The previous pane has gone, not stacked under the new one.
      expect(find.text('월별 출석률'), findsNothing);
      expect(find.text('가상 공약'), findsNothing);
    });

    // A sparkline says nothing to a screen reader, so the shape is spelled
    // out beside it rather than left as decoration.
    testWidgets('describe the sparkline for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);

      await tester.tap(find.text('출석'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'최저 92%, 최고 95%, 최근 95%')),
        findsOneWidget,
      );
      handle.dispose();
    });

    // A district whose activity feed is not wired must still render.
    testWidgets('say so when there is no record behind them', (tester) async {
      await pumpHome(
        tester,
        profileRepository: const FakeProfileRepository(withRecord: false),
      );

      await tester.tap(find.text('법안'));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 연결되지 않았습니다'), findsOneWidget);
    });
  });

  group('the source badge', () {
    // An attribution the reader cannot follow is an assertion. N-4 is about
    // being checkable, not about printing a hostname.
    testWidgets('opens the original it names', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: Scaffold(
            body: SourceBadge(
              source: SourceMetadata.fromJson(_source, field: 'test'),
              onOpen: (url) async => opened.add(url),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SourceBadge));
      await tester.pump();

      expect(opened, [Uri.parse('https://open.assembly.go.kr/fixture')]);
    });
  });
}
