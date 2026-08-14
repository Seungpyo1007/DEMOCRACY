import 'dart:io';

import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/design/app_page_background.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
const goldenPlatforms = {
  'android': TargetPlatform.android,
  'ios': TargetPlatform.iOS,
};

/// Serves the real fixture files straight off disk.
///
/// The screens must show the payload that actually ships, so this reads the
/// same JSON through the same `*.fromJson` the app uses rather than swapping in
/// data shaped to please the test.
///
/// It exists because `rootBundle` does not: asset loads go out over the test
/// binding's message channel, and only the first test in a file gets that
/// round-trip resolved by a plain `pump`. Every later test sat on a spinner and
/// `pumpAndSettle` timed out -- an ordering bug that looked like a platform
/// one, since whichever platform ran second was the one that failed. Reading
/// the file synchronously removes the round-trip and with it the ordering.
class _FixtureFileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // `flutter test` runs with the package root as its working directory, so
    // the asset key is already the path.
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

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
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget screen,
  required TargetPlatform platform,
  bool withDistrict = true,
  bool verified = false,
}) async {
  useGoldenViewport(tester);

  final loader = FixtureLoader(bundle: _FixtureFileBundle());
  final container = ProviderContainer(
    overrides: [
      districtRepositoryProvider.overrideWithValue(
        FakeDistrictRepository(loader: loader),
      ),
      pledgeRepositoryProvider.overrideWithValue(
        FakePledgeRepository(loader: loader),
      ),
      reviewRepositoryProvider.overrideWithValue(
        FakeReviewRepository(loader: loader),
      ),
    ],
  );
  addTearDown(container.dispose);

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
  await tester.pumpAndSettle();
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
