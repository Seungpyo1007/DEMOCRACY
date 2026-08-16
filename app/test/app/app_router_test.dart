import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/fake_address_repositories.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/data/fake_results_repository.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

void main() {
  /// The router is the only thing standing between a deep link and a screen
  /// that assumes a district. It has to be mounted to be tested: a redirect
  /// runs while a route is parsed, and nothing parses until the delegate is in
  /// a tree.
  ///
  /// The repositories are overridden so the destination screens can build --
  /// what is under test is where a navigation lands, not what it renders.
  Future<(ProviderContainer, GoRouter)> pumpRouter(
    WidgetTester tester, {
    DistrictRef? district,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loader = fixtureLoaderFromDisk();
    final container = ProviderContainer(
      overrides: [
        addressSearchRepositoryProvider.overrideWithValue(
          FakeAddressSearchRepository(loader: loader),
        ),
        locationRepositoryProvider.overrideWithValue(
          FakeLocationRepository(loader: loader),
        ),
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
        matchRepositoryProvider.overrideWithValue(
          FakeMatchRepository(loader: loader, tokenDelay: Duration.zero),
        ),
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

    if (district != null) {
      container
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: district);
    }

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    // Bounded rather than settled: the results screen's LIVE dot never rests.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    return (container, router);
  }

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  group('without a district', () {
    testWidgets('starts at onboarding', (tester) async {
      final (_, router) = await pumpRouter(tester);
      expect(locationOf(router), AppRoutes.onboarding);
    });

    // initialLocation alone stops nothing once a URL can be handed in from
    // outside, which is the whole reason the redirect exists.
    for (final route in const [
      AppRoutes.home,
      AppRoutes.tracker,
      AppRoutes.aiMatch,
      AppRoutes.community,
      AppRoutes.results,
    ]) {
      testWidgets('turns a deep link to $route around', (tester) async {
        final (_, router) = await pumpRouter(tester);

        router.go(route);
        await tester.pump();

        expect(locationOf(router), AppRoutes.onboarding);
      });
    }

    testWidgets('turns a pushed pledge detail around too', (tester) async {
      final (_, router) = await pumpRouter(tester);

      router.go(AppRoutes.pledgeDetail('fixture-pledge-1'));
      await tester.pump();

      expect(locationOf(router), AppRoutes.onboarding);
    });
  });

  group('with a district', () {
    testWidgets('lets every tab through', (tester) async {
      final (_, router) = await pumpRouter(tester, district: _district);

      for (final route in const [
        AppRoutes.home,
        AppRoutes.tracker,
        AppRoutes.aiMatch,
        AppRoutes.community,
        AppRoutes.results,
      ]) {
        router.go(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(locationOf(router), route);
      }
    });

    testWidgets('lets the deep-linked routes through', (tester) async {
      final (_, router) = await pumpRouter(tester, district: _district);

      router.go(AppRoutes.pledgeDetail('fixture-pledge-1'));
      await tester.pump();
      expect(locationOf(router), '/tracker/pledges/fixture-pledge-1');

      router.go(AppRoutes.algorithmLog);
      await tester.pump();
      expect(locationOf(router), AppRoutes.algorithmLog);
    });

    // A resident who skipped verification routes back here from a write gate
    // to upgrade the session. Bouncing them out because they already have a
    // district would strand that prompt.
    testWidgets('still allows a return to onboarding', (tester) async {
      final (_, router) = await pumpRouter(tester, district: _district);

      router.go(AppRoutes.onboarding);
      await tester.pump();

      expect(locationOf(router), AppRoutes.onboarding);
    });
  });

  group('the guard reads on navigation, not on state change', () {
    // It uses ref.read and has no refreshListenable, so acquiring a district
    // does not by itself move anyone. That is deliberate -- onboarding
    // navigates when it is finished -- but it is worth pinning, because
    // someone adding a refreshListenable later would change where a resident
    // lands mid-flow.
    testWidgets('acquiring a district does not navigate on its own', (
      tester,
    ) async {
      final (container, router) = await pumpRouter(tester);
      expect(locationOf(router), AppRoutes.onboarding);

      container
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: _district);
      await tester.pump();

      expect(locationOf(router), AppRoutes.onboarding);
    });

    testWidgets('losing a district only bites at the next navigation', (
      tester,
    ) async {
      final (container, router) = await pumpRouter(tester, district: _district);
      router.go(AppRoutes.tracker);
      await tester.pump();
      expect(locationOf(router), AppRoutes.tracker);

      container.read(addressControllerProvider.notifier).continueReadOnly();
      await tester.pump();
      expect(
        locationOf(router),
        AppRoutes.tracker,
        reason: 'no refreshListenable, so nothing re-evaluates yet',
      );

      router.go(AppRoutes.results);
      await tester.pump();
      expect(locationOf(router), AppRoutes.onboarding);
    });
  });
}
