import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_direction_repository.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
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
        expect(find.textContaining('주거 법안 비중이 가장 큽니다'), findsOneWidget);
        expect(find.text('발의 법안 31건 · AI 요약'), findsOneWidget);

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
    // All three sections are model output, so each is marked where it opens.
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}: labels every AI-derived section', (
        tester,
      ) async {
        await pumpDirection(tester, platform: platform);

        for (final header in ['01 후보 정책 성향', '02 의원 행보 추세', '03 지역 쟁점 흐름']) {
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

  testWidgets('switches to the candidate match', (tester) async {
    await pumpDirection(tester);

    await tester.tap(find.text('후보 매칭'));
    await tester.pumpAndSettle();

    expect(find.text('나에게 유리한 후보는?'), findsWidgets);
    expect(find.text('어디로 향하고 있나'), findsNothing);
  });
}

/// A toolbar action by its label: the Material tooltip on Android, the glass
/// button's semantics label on iOS.
Finder _action(TargetPlatform platform, String label) =>
    platform == TargetPlatform.android
    ? find.byTooltip(label)
    : find.bySemanticsLabel(label);
