import 'dart:async';

import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_page_background.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_direction_repository.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_page.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/history/application/history_providers.dart';
import 'package:democracy/src/features/history/data/fake_history_repository.dart';
import 'package:democracy/src/features/history/presentation/history_screen.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_tracker_screen.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/data/fake_results_repository.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fixture_bundle.dart';

/// The page runs under the tab bar, and some pages float an action above it.
/// Both are easy to get wrong in a way no screen test notices, because a
/// screen test pumps the screen without the shell: the tracker's last rows
/// sat behind its report button for two rounds of review.
///
/// So these pump the real router and shell on a phone-sized surface with a
/// home indicator, scroll each page to its end, and measure.
void main() {
  const district = DistrictRef(
    id: 'fixture-seoul-mapo-b',
    displayName: '서울 마포구 을',
  );

  Future<void> pumpApp(
    WidgetTester tester,
    TargetPlatform platform,
    String location,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    // A home indicator, as on every current iPhone and gesture-nav Android.
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    final loader = fixtureLoaderFromDisk();
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        districtRepositoryProvider.overrideWithValue(
          FakeDistrictRepository(loader: loader),
        ),
        pledgeRepositoryProvider.overrideWithValue(
          FakePledgeRepository(loader: loader),
        ),
        reviewRepositoryProvider.overrideWithValue(
          FakeReviewRepository(loader: loader),
        ),
        communityRepositoryProvider.overrideWithValue(
          FakeCommunityRepository(loader: loader),
        ),
        historyRepositoryProvider.overrideWithValue(
          FakeHistoryRepository(loader: loader),
        ),
        matchRepositoryProvider.overrideWithValue(
          FakeMatchRepository(loader: loader, tokenDelay: Duration.zero),
        ),
        directionRepositoryProvider.overrideWithValue(
          FakeDirectionRepository(loader: loader),
        ),
        // One snapshot, no polling: a live feed arms a timer that outlives
        // the test.
        resultsRepositoryProvider.overrideWithValue(
          FakeResultsRepository(
            loader: loader,
            interval: Duration.zero,
            ticks: 0,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(addressControllerProvider.notifier)
        .acceptVerification(
          district: district,
          proof: ResidencyVerificationProof(
            opaqueToken: 'layout-token',
            verifiedAt: DateTime.utc(2026, 7, 30),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light(platform),
            builder: AppPageBackground.builder,
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.byType(PlatformAdaptiveTabBar)),
    ).go(location);
    await tester.pumpAndSettle();
  }

  /// Flings the page to its end and settles.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final page = find.byType(CustomScrollView).hitTestable().first;
    for (var i = 0; i < 12; i++) {
      await tester.fling(page, const Offset(0, -900), 3000);
      await tester.pumpAndSettle();
    }
  }

  /// The lowest piece of text the page drew, in global coordinates.
  double lowestTextBottom(WidgetTester tester) {
    final scroll = find.byType(CustomScrollView).hitTestable().first;
    final texts = find.descendant(of: scroll, matching: find.byType(RichText));
    var lowest = 0.0;
    for (final element in texts.evaluate()) {
      final box = element.renderObject! as RenderBox;
      if (!box.attached || !box.hasSize) {
        continue;
      }
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (bottom > lowest && bottom < 844) {
        lowest = bottom;
      }
    }
    return lowest;
  }

  double top(WidgetTester tester, Finder finder) => tester.getRect(finder).top;

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (name, location) in [
      ('district', AppRoutes.home),
      ('history', AppRoutes.history),
      ('tracker', AppRoutes.tracker),
      ('ai match', AppRoutes.aiMatch),
      ('community', AppRoutes.community),
      ('results', AppRoutes.results),
    ]) {
      testWidgets('$platform $name ends above the tab bar', (tester) async {
        await pumpApp(tester, platform, location);
        await scrollToEnd(tester);

        final bar = top(tester, find.byKey(PlatformAdaptiveTabBar.surfaceKey));
        expect(lowestTextBottom(tester), lessThanOrEqualTo(bar));
      });
    }

    testWidgets('$platform tracker ends above its report action', (
      tester,
    ) async {
      await pumpApp(tester, platform, AppRoutes.tracker);
      await scrollToEnd(tester);

      if (platform == TargetPlatform.android) {
        // Android lends the action to the round button beside the bar, as
        // native iOS does; the page floats nothing of its own. The tracker
        // is a page on the home tab now, and still lends it.
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          find.byKey(const ValueKey('tab-accessory-이행 제보')),
          findsOneWidget,
        );
        final bar = top(tester, find.byKey(PlatformAdaptiveTabBar.surfaceKey));
        expect(lowestTextBottom(tester), lessThanOrEqualTo(bar));
        return;
      }
      final action = find.byType(AppPrimaryButton);
      expect(lowestTextBottom(tester), lessThanOrEqualTo(top(tester, action)));
      // And the action itself sits above the bar, not on or under it.
      expect(
        tester.getRect(action).bottom,
        lessThanOrEqualTo(
          top(tester, find.byKey(PlatformAdaptiveTabBar.surfaceKey)),
        ),
      );
    });

    testWidgets('$platform community ends above its write action', (
      tester,
    ) async {
      await pumpApp(tester, platform, AppRoutes.community);
      await scrollToEnd(tester);

      if (platform == TargetPlatform.android) {
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          find.byKey(const ValueKey('tab-accessory-평가 작성')),
          findsOneWidget,
        );
        final bar = top(tester, find.byKey(PlatformAdaptiveTabBar.surfaceKey));
        expect(lowestTextBottom(tester), lessThanOrEqualTo(bar));
        return;
      }
      final action = find.byType(AppPrimaryButton);
      expect(lowestTextBottom(tester), lessThanOrEqualTo(top(tester, action)));
    });
  }

  // 역사 and 트래커 left the tab bar. Both open from the home now -- the
  // tracker from 「공약」 beside the district's name, the history from the
  // row that closes the page -- and both keep the bar and go back home.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform opens the tracker and the history from the home', (
      tester,
    ) async {
      await pumpApp(tester, platform, AppRoutes.home);
      final router = GoRouter.of(
        tester.element(find.byType(PlatformAdaptiveTabBar)),
      );
      String path() => router.routerDelegate.currentConfiguration.uri.path;

      // Android's large app bar draws its title twice, expanded and
      // collapsed; the expanded one is the one on screen.
      await tester.tap(
        find.byKey(DistrictHomeKeys.pledges).hitTestable().first,
      );
      await tester.pumpAndSettle();
      expect(path(), AppRoutes.tracker);
      expect(find.byType(PledgeTrackerScreen), findsOneWidget);
      expect(find.byKey(PlatformAdaptiveTabBar.surfaceKey), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(path(), AppRoutes.home);

      await tester.scrollUntilVisible(
        find.byKey(DistrictHomeKeys.history),
        300,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DistrictHomeKeys.history));
      await tester.pumpAndSettle();
      expect(path(), AppRoutes.history);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.byKey(PlatformAdaptiveTabBar.surfaceKey), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(path(), AppRoutes.home);
    });
  }

  // A pledge opens from the home's summary straight over the home, with no
  // tracker beneath to lend the report to the bar. The page floats it
  // itself then, so reporting stays one tap away from either path.
  testWidgets('android pledge detail keeps its report action either way', (
    tester,
  ) async {
    await pumpApp(tester, TargetPlatform.android, AppRoutes.home);
    final router = GoRouter.of(
      tester.element(find.byType(PlatformAdaptiveTabBar)),
    );
    const accessory = ValueKey('tab-accessory-이행 제보');

    // Over the tracker: the bar's round button carries it.
    router.go(AppRoutes.pledgeDetail('fixture-pledge-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(accessory), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Straight from the home: the page floats it.
    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    unawaited(router.push(AppRoutes.pledgeDetail('fixture-pledge-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(accessory), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  // 후보 매칭 | 방향 분석 is a switch, not navigation. As a nested route the
  // direction view was pushed over the match with a page transition and a
  // back gesture.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform switches AI views in place, not by pushing', (
      tester,
    ) async {
      await pumpApp(tester, platform, AppRoutes.aiMatch);
      final router = GoRouter.of(
        tester.element(find.byType(PlatformAdaptiveTabBar)),
      );

      router.go(AppRoutes.aiDirection);
      await tester.pumpAndSettle();

      expect(find.byType(AiTabPage), findsOneWidget);
      expect(router.canPop(), isFalse);
    });
  }
}
