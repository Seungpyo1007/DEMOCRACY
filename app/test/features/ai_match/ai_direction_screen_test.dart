import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_direction_repository.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_direction_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

void main() {
  Future<void> pumpDirection(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    DirectionRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        matchRepositoryProvider.overrideWithValue(
          FakeMatchRepository(
            loader: fixtureLoaderFromDisk(),
            tokenDelay: Duration.zero,
          ),
        ),
        directionRepositoryProvider.overrideWithValue(
          repository ??
              FakeDirectionRepository(loader: fixtureLoaderFromDisk()),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    final router = GoRouter(
      initialLocation: AppRoutes.aiDirection,
      routes: [
        GoRoute(
          path: AppRoutes.aiMatch,
          builder: (context, state) => const AiMatchScreen(),
          routes: [
            GoRoute(
              path: AppRoutes.algorithmLogSegment,
              builder: (context, state) => const AlgorithmLogScreen(),
            ),
            GoRoute(
              path: AppRoutes.aiDirectionSegment,
              builder: (context, state) => const AiDirectionScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

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
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('on ${platform.name}', () {
      testWidgets('renders all three sections', (tester) async {
        await pumpDirection(tester, platform: platform);

        expect(find.text('어디로 향하고 있나'), findsWidgets);
        expect(find.text('서울 마포구 을'), findsOneWidget);
        expect(find.text('01 후보 정책 성향', findRichText: true), findsOneWidget);

        await scrollTo(tester, find.text('02 의원 행보 추세', findRichText: true));
        await scrollTo(tester, find.text(trendBasis));
        expect(find.textContaining('복지·보건 분야 비중이 가장 큽니다'), findsOneWidget);
        expect(find.text('21대 13건 · 22대 18건 · 위원회 미정 2건 제외'), findsOneWidget);

        await scrollTo(tester, find.text('03 지역 쟁점 흐름', findRichText: true));
        await scrollTo(tester, find.text('언급 많은 순, 좋고 나쁨 아님'));
        expect(find.text('청년 주거'), findsOneWidget);
        expect(find.text('↗ 언급 늘어남'), findsNWidgets(2));
        expect(find.text('→ 비슷함'), findsOneWidget);
        expect(find.text('↘ 언급 줄어듦'), findsOneWidget);
        expect(find.text('41건', findRichText: true), findsOneWidget);
      });
    });
  }

  group('01 후보 정책 성향', () {
    // N-1, N-2: every candidate is on the plot, and none is set apart.
    testWidgets('places every candidate, named the same way', (tester) async {
      await pumpDirection(tester);

      for (final name in ['가상 후보 가', '가상 후보 나', '가상 후보 다']) {
        final text = tester.widget<Text>(find.text(name));
        expect(text.style?.color, isNotNull);
        expect(
          text.style,
          tester.widget<Text>(find.text('가상 후보 가')).style,
          reason: '$name must be set exactly like the others',
        );
      }
      expect(find.text('등록 공약 45건 문구 기준'), findsOneWidget);
      expect(find.text('점 크기·색은 모두 같게\n위치는 문구만 반영'), findsOneWidget);
    });

    testWidgets('publishes the axis definitions', (tester) async {
      await pumpDirection(tester);

      await tester.tap(find.text('축 정의 공개 ↗'));
      await tester.pumpAndSettle();

      expect(find.text('축 정의'), findsOneWidget);
      expect(find.text('성장 중심 ↔ 분배 중심'), findsOneWidget);
      expect(find.text('규제 강화 ↔ 자율 확대'), findsOneWidget);
    });

    testWidgets('describes the plot to a screen reader', (tester) async {
      await pumpDirection(tester);

      expect(find.bySemanticsLabel(RegExp('후보 3명의 정책 성향 위치')), findsOneWidget);
    });
  });

  // N-4: every section says where its figures came from.
  testWidgets('sources every section', (tester) async {
    await pumpDirection(tester);

    await scrollTo(tester, find.text('언급 많은 순, 좋고 나쁨 아님'));

    // Three sections, three badges. Lazily built slivers may have dropped the
    // first one by now, so count across both ends of the scroll.
    final seen = <String>{
      for (final badge in tester.widgetList<SourceBadge>(
        find.byType(SourceBadge, skipOffstage: false),
      ))
        badge.source.publisher,
    };
    expect(seen, containsAll(['open.assembly.go.kr', 'epeople.go.kr']));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SourceBadge>(find.byType(SourceBadge))
          .map((badge) => badge.source.publisher),
      contains('info.nec.go.kr'),
    );
  });

  group('the disclosure', () {
    // The stances and issues are model output, so each is marked where it
    // opens. The bill trend is a count and is not.
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}: labels every AI-derived section', (
        tester,
      ) async {
        await pumpDirection(tester, platform: platform);

        for (final header in ['01 후보 정책 성향', '03 지역 쟁점 흐름']) {
          final finder = find.text(header, findRichText: true);
          await scrollTo(tester, finder);
          final row = find.ancestor(
            of: finder,
            matching: find.byType(SectionHeader),
          );
          expect(
            find.descendant(of: row, matching: find.byType(AiReferenceLabel)),
            findsOneWidget,
            reason: header,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not call the bill trend AI', (tester) async {
      await pumpDirection(tester);

      await scrollTo(tester, find.text('02 의원 행보 추세', findRichText: true));
      await scrollTo(tester, find.text(trendBasis));
      final trend = find.ancestor(
        of: find.text(trendBasis),
        matching: _trendSection,
      );
      expect(trend, findsOneWidget);

      expect(
        find.descendant(of: trend, matching: find.byType(AiReferenceLabel)),
        findsNothing,
      );
      expect(
        find.descendant(of: trend, matching: find.textContaining('AI')),
        findsNothing,
      );
      expect(find.text(trendBasis), findsOneWidget);
    });

    // iOS, where no app bar brings a persistent header of its own.
    testWidgets('no longer pins a band over the analysis', (tester) async {
      await pumpDirection(tester, platform: TargetPlatform.iOS);

      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(find.text(aiDisclosure), findsNothing);
    });

    testWidgets('links to the open algorithm from the notice', (tester) async {
      await pumpDirection(tester);

      await tester.tap(find.byType(AiReferenceLabel).first);
      await tester.pumpAndSettle();
      expect(find.textContaining(aiDisclosure), findsOneWidget);

      await tester.tap(find.text('알고리즘 검증'));
      await tester.pumpAndSettle();

      expect(find.text('알고리즘 검증'), findsOneWidget);
      expect(find.textContaining('axisWeights'), findsOneWidget);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}: the ⓘ reopens the notice', (tester) async {
        await pumpDirection(tester, platform: platform);

        await tester.tap(_action(platform, 'AI 분석 안내'));
        await tester.pumpAndSettle();

        expect(find.text('AI 분석 안내'), findsOneWidget);
        expect(find.textContaining(aiDisclosure), findsOneWidget);
      });
    }
  });

  // What a live build gets today: the bill count, and nothing model-derived.
  group('trend only', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}: draws the trend, 준비 중 for the rest', (
        tester,
      ) async {
        await pumpDirection(
          tester,
          platform: platform,
          repository: _StaticDirection(_trendOnly()),
        );

        expect(find.text('01 후보 정책 성향', findRichText: true), findsOneWidget);
        expect(find.text('후보 공약 문구의 정책 성향 분석은 아직 준비 중입니다.'), findsOneWidget);
        expect(find.text('02 의원 행보 추세', findRichText: true), findsOneWidget);
        await scrollTo(tester, find.text(trendBasis));
        expect(find.text('가상 의원 · 대표발의 비중'), findsOneWidget);
        expect(find.text('21대 0건 · 22대 3건'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('국토·교통 집계 없음에서 100%')), findsOne);
        await scrollTo(tester, find.text('지역 쟁점 흐름 분석은 아직 준비 중입니다.'));

        // Nothing on the page is AI output, so nothing is labelled as such,
        // and nothing asked for the disclosure scope and failed.
        expect(find.byType(AiReferenceLabel), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('nothing', () {
    testWidgets('an empty report says 준비 중 under every header', (tester) async {
      await pumpDirection(
        tester,
        repository: _StaticDirection(
          const DirectionReport(
            stances: null,
            trend: null,
            issues: null,
            generatedAt: null,
          ),
        ),
      );

      expect(find.text('후보 공약 문구의 정책 성향 분석은 아직 준비 중입니다.'), findsOneWidget);
      expect(find.text('현직 의원의 대표발의 법안 집계는 아직 준비 중입니다.'), findsOneWidget);
      expect(find.text('지역 쟁점 흐름 분석은 아직 준비 중입니다.'), findsOneWidget);
      expect(find.byType(AiReferenceLabel), findsNothing);
      expect(find.byType(SourceBadge), findsNothing);
    });

    testWidgets('a district with no data at all is 준비 중, not an error', (
      tester,
    ) async {
      await pumpDirection(tester, repository: const _UnavailableDirection());

      expect(find.text('이 지역구의 방향 분석은 아직 준비 중입니다.'), findsOneWidget);
      expect(find.text('분석 결과를 불러오지 못했습니다.'), findsNothing);
    });
  });

  testWidgets('switches to the candidate match', (tester) async {
    await pumpDirection(tester);

    await tester.tap(find.text('후보 매칭'));
    await tester.pumpAndSettle();

    expect(find.text('나에게 유리한 후보는?'), findsWidgets);
    expect(find.text('어디로 향하고 있나'), findsNothing);
  });
}

final _trendSection = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_TrendSection',
);

/// A member first elected in the 22대: no 21대 point at all.
DirectionReport _trendOnly() => DirectionReport.fromJson({
  'trend': {
    'legislatorName': '가상 의원',
    'fromTerm': '21대',
    'toTerm': '22대',
    'billCount': 3,
    'fromCount': 0,
    'toCount': 3,
    'excludedCount': 0,
    'fields': [
      {'label': '국토·교통', 'from': null, 'to': 100},
    ],
    'summary':
        '22대에는 국토·교통 분야 법안 비중이 가장 큽니다(100%). '
        '21대에는 집계된 대표발의 법안이 없습니다.',
    'source': {
      'sourceUrl':
          'https://open.assembly.go.kr/portal/data/service/selectAPIServicePage.do/OK7XM1000938DS17215',
      'fetchedAt': '2026-09-24T03:00:00.000Z',
    },
  },
  'stances': null,
  'issues': null,
});

class _StaticDirection implements DirectionRepository {
  const _StaticDirection(this.report);

  final DirectionReport report;

  @override
  Future<DirectionReport> loadReport(String districtId) async => report;
}

class _UnavailableDirection implements DirectionRepository {
  const _UnavailableDirection();

  @override
  Future<DirectionReport> loadReport(String districtId) =>
      Future.error(const NotAvailableException('direction'));
}

/// A toolbar action by its label: the Material tooltip on Android, the glass
/// button's semantics label on iOS.
Finder _action(TargetPlatform platform, String label) =>
    platform == TargetPlatform.android
    ? find.byTooltip(label)
    : find.bySemanticsLabel(label);
