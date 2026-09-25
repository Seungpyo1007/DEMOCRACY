import 'dart:async';

import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_repository.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
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
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
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

  /// The page on top: a pushed page's own location, not the tab beneath it.
  String locationOf(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    return configuration.isEmpty
        ? configuration.uri.path
        : Uri.parse(configuration.last.matchedLocation).path;
  }

  group('without a district', () {
    testWidgets('starts at onboarding', (tester) async {
      final (_, router) = await pumpRouter(tester);
      expect(locationOf(router), AppRoutes.onboarding);
    });

    // initialLocation alone stops nothing once a URL can be handed in from
    // outside, which is the whole reason the redirect exists.
    for (final route in const [
      AppRoutes.home,
      AppRoutes.history,
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
        AppRoutes.history,
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

      router.go(AppRoutes.aiDirection);
      await tester.pump();
      expect(locationOf(router), AppRoutes.aiDirection);
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

  group('the guard re-runs when the state changes', () {
    // Acquiring a district leaves the resident where they are: onboarding
    // navigates itself when it is finished, and moving them mid-flow would
    // skip its last step.
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

    // HANDOFF's known gap: this used to wait for the next navigation.
    testWidgets('losing a district sends the reader to onboarding at once', (
      tester,
    ) async {
      final (container, router) = await pumpRouter(tester, district: _district);
      router.go(AppRoutes.tracker);
      await tester.pump();
      expect(locationOf(router), AppRoutes.tracker);

      container.read(addressControllerProvider.notifier).continueReadOnly();
      await tester.pump();

      expect(locationOf(router), AppRoutes.onboarding);
    });
  });

  group('account routes', () {
    testWidgets('a first sign-in goes through consent to where it began', (
      tester,
    ) async {
      final (container, router) = await pumpRouter(tester, district: _district);
      router.go(AppRoutes.community);
      await tester.pumpAndSettle();
      // The write gate pushes login over the tab it was opened from.
      unawaited(
        router.push(AppRoutes.withNext(AppRoutes.login, AppRoutes.community)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.consent);

      for (final label in ['만 14세 이상입니다', '이용약관', '개인정보 수집·이용']) {
        await tester.tap(find.textContaining(label).first);
        await tester.pump();
      }
      await tester.ensureVisible(find.text('동의하고 시작하기'));
      await tester.tap(find.text('동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider), isA<AuthSignedIn>());
      expect(locationOf(router), AppRoutes.community);
    });

    testWidgets('under 14 ends on its own page with no account', (
      tester,
    ) async {
      final (container, router) = await pumpRouter(tester, district: _district);
      unawaited(router.push(AppRoutes.login));
      await tester.pumpAndSettle();
      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('만 14세 미만이에요'));
      await tester.pumpAndSettle();

      expect(locationOf(router), AppRoutes.under14);
      expect(container.read(authControllerProvider), isA<AuthUnder14>());
    });
  });

  group('writing for the first time', () {
    testWidgets('the gate leads through sign-in and the address check back '
        'to the page, which is then writable', (tester) async {
      final (container, router) = await pumpRouter(tester, district: _district);
      router.go(AppRoutes.community);
      await tester.pumpAndSettle();

      await tester.tap(find.text('평가 작성').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그인하고 계속'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pumpAndSettle();
      for (final label in ['만 14세 이상입니다', '이용약관', '개인정보 수집·이용']) {
        await tester.tap(find.textContaining(label).first);
        await tester.pump();
      }
      await tester.ensureVisible(find.text('동의하고 시작하기'));
      await tester.tap(find.text('동의하고 시작하기'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.residency);

      await tester.tap(find.text('주소로 인증 시작'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '월드컵북로');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('서울 마포구 월드컵북로 400'));
      await tester.pumpAndSettle();
      expect(locationOf(router), AppRoutes.residencyDone);

      await tester.tap(find.text('쓰던 곳으로 돌아가기'));
      await tester.pumpAndSettle();

      expect(locationOf(router), AppRoutes.community);
      expect(container.read(writeAccessProvider), WriteAccess.allowed);
      expect(container.read(addressControllerProvider).isVerified, isTrue);
    });
  });

  group('accountRedirect', () {
    const account = Account(
      userId: 'u',
      provider: SignInProvider.kakao,
      handle: '솔숲 27',
    );
    const session = AuthSession(userId: 'u', provider: SignInProvider.kakao);
    final cases = <(String, AuthState, String?)>[
      // Reading is never redirected, signed in or not.
      (AppRoutes.home, const AuthSignedOut(), null),
      (AppRoutes.community, const AuthSignedOut(), null),
      // Private pages want an account and come back afterwards.
      (AppRoutes.account, const AuthSignedOut(), '/login?next=%2Faccount'),
      (
        AppRoutes.residencyAddress,
        const AuthSignedOut(),
        '/login?next=%2Fresidency%2Faddress',
      ),
      (AppRoutes.account, const AuthSignedIn(account: account), null),
      // Signed in: the login pages hand over to where the reader was going.
      (
        '/login?next=%2Fcommunity',
        const AuthSignedIn(account: account),
        '/community',
      ),
      ('/login/code', const AuthSignedIn(account: account), AppRoutes.home),
      // Half signed in: consent first.
      (
        '/login?next=%2Fcommunity',
        const AuthNeedsConsent(session: session, handleOptions: []),
        '/consent?next=%2Fcommunity',
      ),
      // Consent only while it is owed.
      (AppRoutes.consent, const AuthSignedOut(), AppRoutes.login),
      (AppRoutes.consent, const AuthUnder14(), AppRoutes.under14),
      (AppRoutes.under14, const AuthSignedOut(), AppRoutes.home),
    ];
    for (final (location, auth, expected) in cases) {
      test('$location while ${auth.runtimeType} → $expected', () {
        expect(accountRedirect(Uri.parse(location), auth), expected);
      });
    }
  });
}
