@Tags(['golden'])
library;

import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/account/presentation/consent_screen.dart';
import 'package:democracy/src/features/account/presentation/login_screens.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_direction_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/history/presentation/history_screen.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_detail_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_tracker_screen.dart';
import 'package:democracy/src/features/results/presentation/election_results_screen.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden_harness.dart';

/// The 390dp Android/iOS golden required by `docs/INITIAL_PLAN.md`, and the
/// last of its eight mandatory tests to be implemented.
///
/// Two things about what these images actually contain:
///
/// `flutter test` substitutes a deterministic test font for the system face and
/// disables shadows, so body text renders as blocks. That is expected: body
/// text is the platform face, which the test engine does not have. The
/// bundled serif and pen faces are registered by `flutter_test_config.dart`,
/// so titles, figures and margin notes render as themselves. Every entrance
/// animation is settled before the picture is taken, so these are the end
/// state a reader sees.
///
/// Rasterisation still differs between macOS and Linux, so generation and
/// verification are pinned to macOS. The ubuntu CI job excludes the `golden`
/// tag; a macOS job runs it. Regenerate with:
///
///     TZ=UTC flutter test --tags golden --update-goldens
///
/// TZ is fixed because `SourceMetadata.asOfLabel` renders in local time, and
/// the fixtures are stamped 09:00Z -- far enough from midnight for every
/// plausible CI and developer timezone, but the goldens compare byte for byte,
/// so the date is pinned rather than left to the host.
void main() {
  test(
    'the fixtures the goldens render are on disk where they are read from',
    expectFixturesReadableFromDisk,
  );

  goldenPlatforms.forEach((name, platform) {
    // All three steps, because they are three different screens sharing a
    // frame and only the first was ever pinned.
    for (final step in OnboardingStep.values) {
      testWidgets('onboarding ${step.name} at 390dp on $name', (tester) async {
        await pumpGolden(
          tester,
          screen: const OnboardingScreen(),
          platform: platform,
          // Onboarding is the screen a resident reaches before having one.
          withDistrict: false,
          onboardingStep: step,
        );

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/onboarding_${step.name}_${name}_390dp.png',
          ),
        );
      });
    }

    testWidgets('district home at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const DistrictHomeScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/district_home_${name}_390dp.png'),
      );
    });

    testWidgets('history at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const HistoryScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/history_${name}_390dp.png'),
      );
    });

    testWidgets('pledge tracker at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const PledgeTrackerScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tracker_${name}_390dp.png'),
      );
    });

    testWidgets('pledge detail at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        // The reversed one, since it is the only status whose detail carries
        // a required extra block.
        screen: const PledgeDetailScreen(pledgeId: 'fixture-pledge-19'),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/pledge_detail_${name}_390dp.png'),
      );
    });

    testWidgets('ai match at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const AiMatchScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ai_match_${name}_390dp.png'),
      );
    });

    testWidgets('ai direction at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const AiDirectionScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ai_direction_${name}_390dp.png'),
      );
    });

    testWidgets('election results at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const ElectionResultsScreen(),
        platform: platform,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/results_${name}_390dp.png'),
      );
    });

    // The poll tab, because the disclosure is dense two-line text at 390dp and
    // is the layout in this screen most likely to overflow.
    testWidgets('election poll disclosure at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const ElectionResultsScreen(),
        platform: platform,
      );

      await tester.tap(find.text('여론조사 비교'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/results_polls_${name}_390dp.png'),
      );
    });

    // The state nobody looks at by hand and the one that must never regress
    // quietly. A clock an hour before the fixture's close puts both embargoes
    // on at once: no map, no count, and the poll tab replaced by its notice.
    testWidgets('election results under an embargo at 390dp on $name', (
      tester,
    ) async {
      final container = await pumpGolden(
        tester,
        screen: const ElectionResultsScreen(),
        platform: platform,
        now: KstInstant.seoul(2026, 4, 15, 17),
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/results_embargo_${name}_390dp.png'),
      );

      container.dispose();
    });

    testWidgets('community at 390dp on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const CommunityScreen(),
        platform: platform,
        // Verified, so the write action is drawn live rather than gated --
        // the gated state is covered by the widget tests.
        verified: true,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/community_${name}_390dp.png'),
      );
    });

    testWidgets('login at 390dp on $name', (tester) async {
      await pumpGolden(tester, screen: const LoginScreen(), platform: platform);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login_${name}_390dp.png'),
      );
    });

    testWidgets('consent at 390dp on $name', (tester) async {
      final container = await pumpGolden(
        tester,
        screen: const ConsentScreen(),
        platform: platform,
      );
      // A first sign-in: the consent screen is only ever reached signed in
      // with no profile yet.
      await container
          .read(authControllerProvider.notifier)
          .signIn(SignInProvider.kakao);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/consent_${name}_390dp.png'),
      );
    });
  });
}
