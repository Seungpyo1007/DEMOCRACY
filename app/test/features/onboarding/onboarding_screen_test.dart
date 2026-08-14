import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/fake_address_repositories.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

void main() {
  Future<ProviderContainer> pumpOnboarding(
    WidgetTester tester, {
    LocationFailure? locationOutcome,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final loader = fixtureLoaderFromDisk();
    final container = ProviderContainer(
      overrides: [
        addressSearchRepositoryProvider.overrideWithValue(
          FakeAddressSearchRepository(loader: loader),
        ),
        locationRepositoryProvider.overrideWithValue(
          FakeLocationRepository(outcome: locationOutcome, loader: loader),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A real router, because both exits from this screen navigate and
    // `context.go` throws without one. The destination is a stub: what these
    // tests check is the address state left behind, not the home screen.
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('홈')),
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

  Future<void> resolveDistrict(WidgetTester tester) async {
    await tester.tap(find.text('현재 위치(GPS)로 자동 설정'));
    await tester.pumpAndSettle();
  }

  group('the address step', () {
    testWidgets('cannot be advanced before a district is chosen', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
        reason: 'skipping still needs a district to skip into',
      );

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('resolves a district from the device location', (tester) async {
      await pumpOnboarding(tester);
      await resolveDistrict(tester);

      expect(find.text('감지된 지역구'), findsOneWidget);
      expect(find.text('서울 마포구 을'), findsOneWidget);
      expect(find.text('✓ 인증 가능'), findsOneWidget);
    });

    // The guide requires a manual fallback rather than an error, so a refusal
    // has to leave the screen usable.
    for (final failure in LocationFailure.values) {
      testWidgets('explains ${failure.name} and keeps manual search open', (
        tester,
      ) async {
        await pumpOnboarding(tester, locationOutcome: failure);
        await resolveDistrict(tester);

        expect(find.textContaining(failure.message), findsOneWidget);
        expect(find.textContaining('주소로 직접 찾아'), findsOneWidget);
        expect(find.text('도로명 주소 검색'), findsOneWidget);
      });
    }

    testWidgets('finds a district through the search sheet', (tester) async {
      await pumpOnboarding(tester, locationOutcome: LocationFailure.failed);

      await tester.tap(find.text('도로명 주소 검색'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '월드컵북로');
      await tester.pumpAndSettle();

      await tester.tap(find.text('서울 마포구 월드컵북로 400'));
      await tester.pumpAndSettle();

      expect(find.text('감지된 지역구'), findsOneWidget);
      expect(find.text('서울 마포구 을'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('도로명 주소 검색'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '없는주소');
      await tester.pumpAndSettle();

      expect(find.textContaining('검색 결과가 없습니다'), findsOneWidget);
    });
  });

  group('the profile step', () {
    testWidgets('is optional -- the CTA stays live with nothing chosen', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('프로필 (AI 분석용 · 선택)'), findsOneWidget);
      expect(find.text('설정하지 않음 · 나중에 바꿀 수 있습니다'), findsNothing);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('설정하지 않음 · 나중에 바꿀 수 있습니다'), findsOneWidget);
    });

    testWidgets('offers every tag the guide lists and keeps the choices', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      for (final tag in ResidentProfile.availableTags) {
        expect(find.textContaining(tag), findsWidgets, reason: 'missing $tag');
      }

      await tester.tap(find.text('세금'));
      await tester.pumpAndSettle();

      expect(container.read(residentProfileProvider).tags, contains('세금'));
    });
  });

  group('completing the flow', () {
    // Until now nothing in the running app called acceptVerification, so the
    // verified state was reachable only from a test and every write gate was
    // permanently shut.
    testWidgets('is the first path that reaches a verified resident', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      expect(container.read(addressControllerProvider).isVerified, isFalse);

      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('주민 인증 완료'));
      await tester.pumpAndSettle();

      final address = container.read(addressControllerProvider);
      expect(address.isVerified, isTrue);
      expect(address.district?.id, 'fixture-seoul-mapo-b');
      expect(address.verification?.opaqueToken, isNotEmpty);
    });

    testWidgets('skipping leaves the resident read-only with a district', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      await resolveDistrict(tester);

      await tester.tap(find.text('나중에 인증하기'));
      await tester.pumpAndSettle();

      final address = container.read(addressControllerProvider);
      expect(address.isVerified, isFalse);
      expect(address.status, AddressStatus.unverified);
      expect(address.district, isNotNull);
    });

    testWidgets('back walks the steps instead of leaving the flow', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      container.read(onboardingControllerProvider.notifier).back();
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        container.read(onboardingControllerProvider).district,
        isNotNull,
        reason: 'stepping back must not discard the district',
      );
    });
  });
}
