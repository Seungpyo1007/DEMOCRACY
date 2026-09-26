import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/fake_address_repositories.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:democracy/src/features/onboarding/presentation/address_search_screen.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/cupertino.dart';
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
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
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
          path: AppRoutes.addressSearch,
          builder: (context, state) => const AddressSearchScreen(),
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

  // The page's own field: the only text field once the page is up.
  final pageField = find.descendant(
    of: find.byType(AddressSearchScreen),
    matching: find.byType(EditableText),
  );

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.text('도로명 주소 검색'));
    await tester.pumpAndSettle();
  }

  Future<void> searchAndPick(WidgetTester tester) async {
    await openSearch(tester);
    await tester.enterText(pageField, '월드컵북로');
    await tester.pumpAndSettle();
    await tester.tap(find.text('서울 마포구 월드컵북로 400'));
    await tester.pumpAndSettle();
  }

  Future<void> resolveDistrict(WidgetTester tester) async {
    await tester.tap(find.text('현재 위치로 자동 설정'));
    await tester.pumpAndSettle();
  }

  group('the address step', () {
    testWidgets('cannot be advanced before a district is chosen', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      OnboardingStep step() =>
          container.read(onboardingControllerProvider).step;

      expect(step(), OnboardingStep.address);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
        reason: 'skipping still needs a district to skip into',
      );

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(step(), OnboardingStep.address);
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

    testWidgets('finds a district on the address search page', (tester) async {
      await pumpOnboarding(tester, locationOutcome: LocationFailure.failed);

      await openSearch(tester);
      expect(find.byType(AddressSearchScreen), findsOneWidget);
      expect(find.text('도로명을 입력하면 지역구를 찾아 드립니다.'), findsOneWidget);
      expect(find.text('주소는 지역구 설정과 주민 인증에만 사용되며 암호화 저장됩니다.'), findsOneWidget);

      await tester.enterText(pageField, '월드컵북로');
      await tester.pumpAndSettle();
      expect(find.text('서울 마포구 을'), findsWidgets);

      await tester.tap(find.text('서울 마포구 월드컵북로 400'));
      await tester.pumpAndSettle();

      expect(find.byType(AddressSearchScreen), findsNothing);
      expect(find.text('감지된 지역구'), findsOneWidget);
      expect(find.text('서울 마포구 을'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpOnboarding(tester);

      await openSearch(tester);
      await tester.enterText(pageField, '없는주소');
      await tester.pumpAndSettle();

      expect(find.textContaining('검색 결과가 없습니다'), findsOneWidget);
    });

    testWidgets('the search page opens as a page, not a sheet', (tester) async {
      await pumpOnboarding(tester);

      expect(find.byType(SearchBar), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, '현재 위치로 자동 설정'),
        findsOneWidget,
      );

      await openSearch(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AddressSearchScreen),
          matching: find.byType(SearchBar),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('뒤로'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressSearchScreen), findsNothing);
      expect(find.text('내 지역구부터\n찾아드릴게요'), findsOneWidget);
    });

    testWidgets('the search page finds a district from the location', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);

      await openSearch(tester);
      await tester.tap(find.text('현재 위치로 찾기'));
      await tester.pumpAndSettle();

      expect(find.byType(AddressSearchScreen), findsNothing);
      expect(
        container.read(onboardingControllerProvider).district?.id,
        'fixture-seoul-mapo-b',
      );
    });

    testWidgets('the search page explains a location failure and stays', (
      tester,
    ) async {
      await pumpOnboarding(tester, locationOutcome: LocationFailure.failed);

      await openSearch(tester);
      await tester.tap(find.text('현재 위치로 찾기'));
      await tester.pumpAndSettle();

      expect(find.byType(AddressSearchScreen), findsOneWidget);
      expect(
        find.textContaining(LocationFailure.failed.message),
        findsOneWidget,
      );
    });

    testWidgets('shows the chosen address on the launcher', (tester) async {
      await pumpOnboarding(tester, locationOutcome: LocationFailure.failed);

      await searchAndPick(tester);

      expect(find.text('서울 마포구 월드컵북로 400'), findsOneWidget);
      final launcher = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '주소 검색',
        ),
      );
      expect(launcher.properties.button, isTrue);
      expect(launcher.properties.value, '서울 마포구 월드컵북로 400');
    });

    testWidgets('iOS takes the Cupertino field and a plain text action', (
      tester,
    ) async {
      await pumpOnboarding(tester, platform: TargetPlatform.iOS);

      expect(find.widgetWithText(CupertinoButton, '나중에 인증하기'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);

      await openSearch(tester);
      expect(find.byType(CupertinoSearchTextField), findsOneWidget);
      expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
      await tester.enterText(pageField, '월드컵북로');
      await tester.pumpAndSettle();
      await tester.tap(find.text('서울 마포구 월드컵북로 400'));
      await tester.pumpAndSettle();
      expect(find.text('서울 마포구 을'), findsOneWidget);
    });
  });

  group('the profile step', () {
    testWidgets('is optional -- the CTA stays live with nothing chosen', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      OnboardingStep step() =>
          container.read(onboardingControllerProvider).step;
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      expect(step(), OnboardingStep.profile);
      expect(find.textContaining('프로필 (AI 분석용 · 선택)'), findsOneWidget);
      expect(find.text('설정하지 않음 · 나중에 바꿀 수 있습니다'), findsNothing);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(step(), OnboardingStep.done);
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

    testWidgets('sets the interest on a five-stop slider', (tester) async {
      final container = await pumpOnboarding(tester);
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, ResidentProfile.interestSteps);
      expect(
        slider.label,
        container.read(residentProfileProvider).interestLabel,
      );

      slider.onChanged!(ResidentProfile.interestSteps.toDouble());
      await tester.pumpAndSettle();

      expect(
        container.read(residentProfileProvider).interest,
        ResidentProfile.interestSteps,
      );
      expect(find.text('매우 높음'), findsWidgets);
    });
  });

  group('completing the flow', () {
    // Residency comes from the server's address check, on an account, and
    // nowhere else: finishing onboarding sets the district for reading only.
    testWidgets('finishing sets the district for reading, not residency', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      expect(container.read(addressControllerProvider).isVerified, isFalse);

      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('지금 주민 인증하기'), findsOneWidget);
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      final address = container.read(addressControllerProvider);
      expect(address.isVerified, isFalse);
      expect(address.district?.id, 'fixture-seoul-mapo-b');
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
      expect(find.text('관심사를 알려주시면\n분석이 정확해져요'), findsOneWidget);

      container.read(onboardingControllerProvider.notifier).back();
      await tester.pumpAndSettle();

      expect(find.text('내 지역구부터\n찾아드릴게요'), findsOneWidget);
      expect(
        find.text('관심사를 알려주시면\n분석이 정확해져요'),
        findsNothing,
        reason: 'the outgoing step must be gone once the transition settles',
      );
      expect(
        container.read(onboardingControllerProvider).district,
        isNotNull,
        reason: 'stepping back must not discard the district',
      );
    });
  });

  group('the redesigned flow', () {
    testWidgets('announces the step the segments show', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOnboarding(tester);
      expect(find.bySemanticsLabel('3단계 중 1단계'), findsOneWidget);

      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('3단계 중 2단계'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the profile step can be skipped to the confirmation', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      await resolveDistrict(tester);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('건너뛰기'));
      await tester.pumpAndSettle();

      expect(
        container.read(onboardingControllerProvider).step,
        OnboardingStep.done,
      );
      expect(find.text('서울 마포구 을'), findsOneWidget);
      expect(
        container.read(addressControllerProvider).district,
        isNull,
        reason: 'skipping the profile is not leaving the flow',
      );
    });

    testWidgets('the address step carries its margin note', (tester) async {
      await pumpOnboarding(tester, platform: TargetPlatform.iOS);

      expect(find.text('당이 아닌 인물로, 감정이 아닌 데이터로'), findsOneWidget);
      expect(find.text('내 지역구부터\n찾아드릴게요'), findsOneWidget);
    });

    testWidgets('steps change without animating under reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpOnboarding(tester);
      await resolveDistrict(tester);

      await tester.tap(find.text('다음'));
      await tester.pump();

      // One frame, and the old step is already gone.
      expect(find.text('내 지역구부터\n찾아드릴게요'), findsNothing);
      expect(find.text('관심사를 알려주시면\n분석이 정확해져요'), findsOneWidget);
    });
  });
}
