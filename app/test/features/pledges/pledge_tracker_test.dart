import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/status_donut.dart';
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
    of: find.byType(StatusLegend),
    matching: find.text(label),
  );

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
        pledgeRepositoryProvider.overrideWithValue(
          FakePledgeRepository(loader: fixtureLoaderFromDisk()),
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
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('종합 이행률'), findsOneWidget);
      expect(legendEntry('✓ 이행 완료'), findsOneWidget);
      expect(find.text('9건 · 38%'), findsOneWidget);
      expect(find.text('8건 · 33%'), findsOneWidget);
      expect(find.text('5건 · 21%'), findsOneWidget);
      expect(find.text('2건 · 8%'), findsOneWidget);
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
      expect(find.text('전체 공약'), findsOneWidget);
      expect(find.text('24건'), findsOneWidget);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();

      expect(find.text('번복 공약'), findsOneWidget);
      expect(find.text('2건'), findsOneWidget);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();

      expect(find.text('전체 공약'), findsOneWidget);
    });
  });

  group('category bars', () {
    // Counting work in progress as a fraction of a kept promise would be the
    // app deciding how much credit partial work earns.
    testWidgets('count only what was kept', (tester) async {
      await pumpTracker(tester);

      // 교육: 2 of 3 fulfilled.
      expect(find.text('교육'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
    });
  });

  group('pledge detail', () {
    testWidgets('opens from the list and shows who judged it', (tester) async {
      await pumpTracker(tester);

      await tester.tap(find.text('환승 개선 사업'));
      await tester.pumpAndSettle();

      expect(find.text('판정 파이프라인'), findsOneWidget);
      expect(find.text('AI 1차 판단'), findsOneWidget);
      expect(find.text('시민 제보 12건'), findsOneWidget);
      expect(find.text('전문가 위원회 최종 판정'), findsOneWidget);
    });

    // Refused at parse time without it, so the link is never missing on the
    // one status where its absence would matter.
    testWidgets('a reversal always carries its evidence link', (tester) async {
      await pumpTracker(tester);

      await tester.tap(legendEntry('↩ 번복'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('숲길 확장'));
      await tester.pumpAndSettle();

      expect(find.text('번복 근거'), findsOneWidget);
      expect(find.text('원문 대조 보기'), findsOneWidget);
    });

    testWidgets('says so when a pledge has no judgement recorded', (
      tester,
    ) async {
      await pumpTracker(tester);

      // Twenty-four pledges: most of the list starts below the fold.
      await tester.scrollUntilVisible(
        find.text('심야버스 노선 확대'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('심야버스 노선 확대'));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 판정 기록이 없습니다'), findsOneWidget);
    });

    // The app had no pushed route at all until now, so nothing could exercise
    // a back stack -- which is also why swipe-back had never been verified.
    testWidgets('is a pushed route, so back returns to the list', (
      tester,
    ) async {
      await pumpTracker(tester);
      await tester.tap(find.text('환승 개선 사업'));
      await tester.pumpAndSettle();
      expect(find.text('판정 파이프라인'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('카테고리별 이행률'), findsOneWidget);
    });
  });

  group('reporting', () {
    testWidgets('is blocked and explained for an unverified resident', (
      tester,
    ) async {
      await pumpTracker(tester);

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.text('주민 인증이 필요합니다'), findsOneWidget);
      expect(find.textContaining('제보 화면은'), findsNothing);
    });

    testWidgets('proceeds for a verified resident', (tester) async {
      await pumpTracker(tester, verified: true);

      await tester.tap(find.text('이행 제보'));
      await tester.pumpAndSettle();

      expect(find.text('주민 인증이 필요합니다'), findsNothing);
      expect(find.textContaining('제보 화면은'), findsOneWidget);
    });
  });
}
