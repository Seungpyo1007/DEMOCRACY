import 'dart:io';

import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_page_background.dart';
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

import 'fixture_bundle.dart';

/// The mockup viewport. `design_handoff_democracy_app` is drawn at 390dp wide,
/// and the golden required by `docs/INITIAL_PLAN.md` is defined at that width.
const goldenSize = Size(390, 844);

/// One logical pixel per device pixel, so the goldens are exactly 390x844.
/// That keeps the files small and keeps the comparison clear of resampling.
const goldenDevicePixelRatio = 1.0;

/// The district the bundled fixtures are keyed to.
const goldenDistrict = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

/// The two platforms the required test names. Both are captured from the same
/// widget tree, so a difference between the files is a real difference in the
/// platform-adaptive layer rather than in the screen.
/// The one canonical "now" the goldens are taken at.
///
/// Deliberately the same Korean calendar day as every fixture's `fetchedAt`
/// (2026-07-30T09:00:00Z), and deliberately far from the fixture's election
/// day, so nothing is embargoed and the committed pictures keep meaning what
/// they meant when they were taken.
final goldenNow = KstInstant.parse(
  '2026-07-30T18:00:00+09:00',
  field: 'goldenNow',
);

const goldenPlatforms = {
  'android': TargetPlatform.android,
  'ios': TargetPlatform.iOS,
};

/// Pins the surface to [goldenSize] for one test and restores it afterwards.
///
/// `tester.view` is shared across a test file, so leaving it changed would
/// silently resize whatever runs next.
void useGoldenViewport(WidgetTester tester) {
  tester.view.physicalSize = goldenSize;
  tester.view.devicePixelRatio = goldenDevicePixelRatio;
  addTearDown(tester.view.reset);
}

/// Builds the app frame a screen sits in, at the golden viewport.
/// Returns the container so a test inside an embargo can dispose it in the
/// body. Inside one there is a deadline ahead, so the results provider arms a
/// timer for it, and the framework checks for pending timers before teardowns
/// run.
Future<ProviderContainer> pumpGolden(
  WidgetTester tester, {
  required Widget screen,
  required TargetPlatform platform,
  bool withDistrict = true,
  bool verified = false,
  OnboardingStep? onboardingStep,

  /// A screen with a deliberately perpetual animation -- the LIVE dot on the
  /// results screen -- can never settle. Pump it a fixed distance instead.
  bool settle = true,

  /// The moment the goldens are taken at.
  ///
  /// It defaults rather than being required, and it is applied here rather
  /// than by each test, because the harness owns the container: a golden that
  /// forgot to pin the clock cannot be written. Without this, the results
  /// golden would start rendering an embargo notice the week of an election
  /// and go back afterwards -- a picture that means something different
  /// depending on the day it is compared.
  KstInstant? now,
}) async {
  useGoldenViewport(tester);

  final loader = fixtureLoaderFromDisk();
  final container = ProviderContainer(
    overrides: [
      addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
      clockProvider.overrideWithValue(FixedClock(now ?? goldenNow)),
      addressSearchRepositoryProvider.overrideWithValue(
        FakeAddressSearchRepository(loader: loader),
      ),
      locationRepositoryProvider.overrideWithValue(
        FakeLocationRepository(loader: loader),
      ),
      resultsRepositoryProvider.overrideWithValue(
        FakeResultsRepository(
          loader: loader,
          interval: Duration.zero,
          ticks: 0,
        ),
      ),
      matchRepositoryProvider.overrideWithValue(
        FakeMatchRepository(loader: loader, tokenDelay: Duration.zero),
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
    ],
  );
  addTearDown(container.dispose);

  // Onboarding is three screens in one frame, so a golden has to say which.
  // Steps past the first need a district, since the flow cannot reach them
  // without one.
  if (onboardingStep != null) {
    final onboarding = container.read(onboardingControllerProvider.notifier);
    if (onboardingStep != OnboardingStep.address) {
      onboarding.selectDistrict(goldenDistrict, address: '서울 마포구 월드컵북로 400');
      onboarding.next();
      if (onboardingStep == OnboardingStep.done) {
        onboarding.next();
      }
    }
  }

  if (withDistrict) {
    final controller = container.read(addressControllerProvider.notifier);
    if (verified) {
      controller.acceptVerification(
        district: goldenDistrict,
        proof: ResidencyVerificationProof(
          opaqueToken: 'golden-opaque-token',
          verifiedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    } else {
      controller.continueReadOnly(district: goldenDistrict);
    }
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(platform),
        // Same builder DemocracyApp uses. Without it the iOS scaffold is
        // transparent by design and the goldens would capture a screen with
        // no page behind it.
        builder: AppPageBackground.builder,
        // Otherwise the debug banner is baked into the corner of every image.
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return container;
}

/// Guards the assumption the disk bundle rests on: the fixture keys the app
/// asks for have to be real paths from the package root.
void expectFixturesReadableFromDisk() {
  for (final name in const [
    'district_fixture-seoul-mapo-b',
    'pledges_fixture-seoul-mapo-b',
    'reviews_fixture-seoul-mapo-b',
  ]) {
    expect(
      File('assets/fixtures/$name.json').existsSync(),
      isTrue,
      reason: 'goldens read $name.json from disk, not from rootBundle',
    );
  }
}
