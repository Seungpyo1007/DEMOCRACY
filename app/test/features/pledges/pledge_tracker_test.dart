import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_detail_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_tracker_screen.dart';
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
  /// Once a filter is applied the status chips render the same text as the
  /// legend, so a bare text finder becomes ambiguous.
  Finder legendEntry(String label) => find.descendant(
    of: find.byKey(PledgeTrackerKeys.legend),
    matching: find.text(label),
  );

  /// The count beside the list's section header. Legend rows and the hero
  /// figure use the same `N건` shape, so the header's own count is keyed.
  String listCount(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(PledgeTrackerKeys.listCount)).data!;

  /// The list sits below the distribution and the category bars, so a row
  /// has to be scrolled into view before it can be tapped.
  Future<void> openPledge(WidgetTester tester, String title) async {
    // Centre-ish rather than just on screen: the bottom edge is where the
    // floating report action sits.
    await Scrollable.ensureVisible(
      tester.element(find.text(title)),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpTracker(
    WidgetTester tester, {
    bool verified = false,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    // The default 800x600 test surface is wider and shorter than any phone,
    // which put list rows under the bottom bar. Matching the mockup viewport
    // makes these tests lay out the way the screen actually does.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        pledgeRepositoryProvider.overrideWithValue(
          FakePledgeRepository(loader: fixtureLoaderFromDisk()),
        ),
        districtRepositoryProvider.overrideWithValue(
          FakeDistrictRepository(loader: fixtureLoaderFromDisk()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(addressControllerProvider.notifier);
    if (verified) {
      controller.acceptVerification(
        district: _district,
        proof: ResidencyVerificationProof(
          opaqueToken: 'fixture-token',
          verifiedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    } else {
      controller.continueReadOnly(district: _district);
    }

    final router = GoRouter(
      initialLocation: AppRoutes.tracker,
      routes: [
        GoRoute(
          path: AppRoutes.tracker,
          builder: (context, state) => const PledgeTrackerScreen(),
          routes: [
            GoRoute(
              path: AppRoutes.pledgeDetailSegment,
              builder: (context, state) =>
                  PledgeDetailScreen(pledgeId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const Scaffold(body: Text('온보딩')),
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
    return container;
  }

  group('the distribution', () {
    testWidgets('breaks the headline into counts, not just a percentage', (
      tester,
    ) async {
      await pumpTracker(tester);

      // 9 of 24 kept.
      final hero = tester.widget<Figure>(
        find.descendant(
          of: find.byKey(PledgeTrackerKeys.heroRate),
          matching: find.byType(Figure),
        ),
      );
      expect('${hero.value}${hero.unit}', '38%');
      expect(
        find.descendant(
          of: find.byKey(PledgeTrackerKeys.heroRate),
          matching: find.text('38%', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Figure && w.value == 24 && w.unit == '건',
        ),
        findsOneWidget,
      );
      expect(find.text('등록 공약'), findsOneWidget);
      expect(find.text('01 종합 이행률'), findsOneWidget);
      expect(legendEntry('✓ 이행 완료'), findsOneWidget);
      for (final (count, percent) in [
        ('9건', '38%'),
        ('8건', '33%'),
        ('5건', '21%'),
        ('2건', '8%'),
      ]) {
        expect(legendEntry(count), findsOneWidget);
        expect(legendEntry(percent), findsOneWidget);
      }
    });

    // The stacked bar is colour only, so a screen reader gets every share.
    testWidgets('the stacked bar names all four shares', (tester) async {
      await pumpTracker(tester);

      expect(
        find.bySemanticsLabel('이행 완료 38%, 진행 중 33%, 미이행 21%, 번복 8%'),
        findsOneWidget,
      );
    });

    // The legend is the only place the donut's colours are named, so it
    // carries the glyph and the word rather than a swatch alone.
    testWidgets('names every colour it uses', (tester) async {
      await pumpTracker(tester);

      for (final status in PledgeStatus.values) {
        expect(find.textContaining(status.label), findsWidgets);
        expect(find.textContaining(status.glyph), findsWidgets);
      }
    });

    testWidgets('filters the list from the legend and clears again', (
      tester,
    ) async {
      await pumpTracker(tester);
      expect(find.text('03 전체 공약'), findsOneWidget);
      expect(listCount(tester), '24건');

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();

      expect(find.text('03 번복 공약'), findsOneWidget);
      expect(listCount(tester), '2건');
      expect(find.text('숲길 확장'), findsOneWidget);
      expect(find.text('환승 개선 사업'), findsNothing);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();

      expect(find.text('03 전체 공약'), findsOneWidget);
      expect(listCount(tester), '24건');
    });

    testWidgets('filters with reduced motion without animating', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpTracker(tester);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pump();

      expect(find.text('03 번복 공약'), findsOneWidget);
      expect(find.text('환승 개선 사업'), findsNothing);
    });

    testWidgets('names the incumbent and district in the kicker', (
      tester,
    ) async {
      await pumpTracker(tester);

      expect(find.text('가상 의원 · 서울 마포구 을'), findsOneWidget);
      // Android's large app bar carries the title twice, expanded and
      // collapsed, and cross-fades between them as the page scrolls.
      expect(find.text('공약이행률 트래커'), findsWidgets);
    });
  });

  group('category bars', () {
    // Counting work in progress as a fraction of a kept promise would be the
    // app deciding how much credit partial work earns.
    testWidgets('count only what was kept', (tester) async {
      await pumpTracker(tester);

      // 교육: 2 of 3 fulfilled.
      final bar = find.widgetWithText(LabeledBar, '교육');
      expect(bar, findsOneWidget);
      expect(tester.widget<LabeledBar>(bar).valueText, '67%');
      expect(tester.widget<LabeledBar>(bar).fraction, closeTo(2 / 3, 1e-9));
    });
  });

  group('pledge detail', () {
    testWidgets('opens from the list and shows who judged it', (tester) async {
      await pumpTracker(tester);

      await openPledge(tester, '환승 개선 사업');

      expect(find.text('01 판정 과정'), findsOneWidget);
      expect(find.text('현재 판정'), findsOneWidget);
      expect(find.text('교통 · 가상 의원'), findsOneWidget);
      expect(find.text('AI 1차 판단'), findsOneWidget);
      expect(find.text('시민 제보 12건'), findsOneWidget);
      expect(find.text('전문가 위원회 최종 판정'), findsOneWidget);
      expect(find.text('판정문 보기 →'), findsOneWidget);
      expect(find.text('판정 근거는 모두 원문으로 연결됩니다'), findsOneWidget);
    });

    // Refused at parse time without it, so the link is never missing on the
    // one status where its absence would matter.
    testWidgets('a reversal always carries its evidence link', (tester) async {
      await pumpTracker(tester);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();
      await openPledge(tester, '숲길 확장');

      expect(find.text('번복 근거'), findsOneWidget);
      expect(find.text('원문 대조 보기'), findsOneWidget);
    });

    testWidgets('says so when a pledge has no judgement recorded', (
      tester,
    ) async {
      await pumpTracker(tester);

      await openPledge(tester, '심야버스 노선 확대');

      expect(find.textContaining('아직 판정 기록이 없습니다'), findsOneWidget);
    });

    testWidgets(
      'says so when the pledge is not on the board, and can go back',
      (tester) async {
        await pumpTracker(tester);
        final router = GoRouter.of(
          tester.element(find.byType(PledgeTrackerScreen)),
        );
        router.push(AppRoutes.pledgeDetail('no-such-pledge'));
        await tester.pumpAndSettle();

        expect(find.text('이 지역구에서 해당 공약을 찾지 못했습니다.'), findsOneWidget);
        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();
        expect(find.text('02 분야별'), findsOneWidget);
      },
    );

    // The app had no pushed route at all until now, so nothing could exercise
    // a back stack -- which is also why swipe-back had never been verified.
    testWidgets('is a pushed route, so back returns to the list', (
      tester,
    ) async {
      await pumpTracker(tester);
      await openPledge(tester, '환승 개선 사업');
      expect(find.text('01 판정 과정'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('02 분야별'), findsOneWidget);
    });

    // iOS draws back as a floating glass button in the top corner, the one
    // the system uses, labelled for screen readers rather than with text.
    testWidgets('on iOS, the glass back button returns to the list', (
      tester,
    ) async {
      await pumpTracker(tester, platform: TargetPlatform.iOS);
      await openPledge(tester, '환승 개선 사업');

      await tester.tap(find.bySemanticsLabel('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('02 분야별'), findsOneWidget);
    });
  });

  group('reporting', () {
    testWidgets('is blocked and explained for an unverified resident', (
      tester,
    ) async {
      await pumpTracker(tester);

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.text('로그인하고 계속'), findsOneWidget);
      expect(find.textContaining('제보 화면은'), findsNothing);
    });

    testWidgets('proceeds for a verified resident', (tester) async {
      await pumpTracker(tester, verified: true);

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.text('로그인하고 계속'), findsNothing);
      expect(find.textContaining('제보 화면은'), findsOneWidget);
    });

    testWidgets('floats the capsule on iOS, gated the same way', (
      tester,
    ) async {
      await pumpTracker(tester, platform: TargetPlatform.iOS);

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.text('로그인하고 계속'), findsOneWidget);
    });

    // Each platform's own control: M3's large app bar and extended FAB on
    // Android, the prominent glass button on the floating bar on iOS.
    testWidgets('uses the native chrome on each platform', (tester) async {
      await pumpTracker(tester);
      expect(find.byType(SliverAppBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(AppFloatingBar), findsNothing);
    });

    // A compact capsule at the end, not a full-width bar: it covers a corner
    // of the list rather than a whole row.
    testWidgets('floats a compact capsule on iOS, with no app bar', (
      tester,
    ) async {
      await pumpTracker(tester, platform: TargetPlatform.iOS);
      expect(find.byType(SliverAppBar), findsNothing);
      final button = tester.getRect(find.byType(AppPrimaryButton));
      expect(button.width, lessThan(390 / 2));
      expect(button.right, greaterThan(390 - 40));
    });

    testWidgets('is offered on the pledge page too', (tester) async {
      await pumpTracker(tester, verified: true);
      await openPledge(tester, '환승 개선 사업');

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.textContaining('제보 화면은'), findsOneWidget);
    });
  });
}
