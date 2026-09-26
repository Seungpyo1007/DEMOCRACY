import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tokens are transcribed from a design bundle rather than derived, so the
/// only thing that keeps them honest is pinning the values that carry a rule.
void main() {
  group('the neutral ramp', () {
    test('runs light to dark without a step going backwards', () {
      const ramp = [
        AppColors.neutral100,
        AppColors.neutral200,
        AppColors.neutral300,
        AppColors.neutral400,
        AppColors.neutral500,
        AppColors.neutral600,
        AppColors.neutral700,
        AppColors.neutral800,
        AppColors.neutral900,
      ];

      for (var i = 1; i < ramp.length; i++) {
        expect(
          ramp[i].computeLuminance(),
          lessThan(ramp[i - 1].computeLuminance()),
          reason: 'neutral${i + 1}00 must be darker than neutral${i}00',
        );
      }
    });
  });

  group('status colours', () {
    // Three statuses are a lightness ramp of ink, so they stay apart without
    // hue -- including for a colour-blind reader -- and the one that does carry
    // hue is the one the eye should land on.
    test('the three non-reversed statuses step down in lightness', () {
      expect(
        AppColors.fulfilled.computeLuminance(),
        lessThan(AppColors.inProgress.computeLuminance()),
      );
      expect(
        AppColors.inProgress.computeLuminance(),
        lessThan(AppColors.unfulfilled.computeLuminance()),
      );
    });

    // The accent is the primary action. The design allows it back into data
    // for exactly one meaning, and a second borrower would make an action
    // colour read as a judgement.
    test('번복 is the only status allowed to reuse the accent', () {
      expect(AppColors.reversed, AppColors.signal);
      for (final other in [
        AppColors.fulfilled,
        AppColors.inProgress,
        AppColors.unfulfilled,
      ]) {
        expect(other, isNot(AppColors.signal));
      }
    });

    test('every status label reads as body text on the page', () {
      for (final text in [
        AppColors.fulfilledText,
        AppColors.inProgressText,
        AppColors.unfulfilledText,
        AppColors.reversedText,
      ]) {
        final ratio =
            (AppColors.ground.computeLuminance() + 0.05) /
            (text.computeLuminance() + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });

    test('every chip pair keeps its label readable on its own fill', () {
      const pairs = [
        (AppColors.fulfilledChipBackground, AppColors.fulfilledChipForeground),
        (
          AppColors.inProgressChipBackground,
          AppColors.inProgressChipForeground,
        ),
        (
          AppColors.unfulfilledChipBackground,
          AppColors.unfulfilledChipForeground,
        ),
        (AppColors.reversedChipBackground, AppColors.reversedChipForeground),
      ];

      for (final (background, foreground) in pairs) {
        final lighter = background.computeLuminance();
        final darker = foreground.computeLuminance();
        final ratio = (lighter + 0.05) / (darker + 0.05);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'chip text must clear WCAG AA against its own background',
        );
      }
    });
  });

  group('typography', () {
    test('nothing is declared below the 10sp floor', () {
      final sizes = <double>[
        ...AppTypography.textTheme.declaredStyles.map(
          (style) => style.fontSize ?? AppTypography.minFontSize,
        ),
        ...AppTextStyles.all.map(
          (style) => style.fontSize ?? AppTypography.minFontSize,
        ),
      ];

      expect(sizes, isNotEmpty);
      for (final size in sizes) {
        expect(size, greaterThanOrEqualTo(AppTypography.minFontSize));
      }
    });

    test('the named scale matches the redesign', () {
      final theme = AppTypography.textTheme;
      expect(theme.displaySmall?.fontSize, 34);
      expect(theme.displaySmall?.fontFamily, AppFonts.serif);
      expect(theme.titleLarge?.fontSize, 24);
      expect(theme.bodyLarge?.fontSize, 15);
      expect(theme.bodyLarge?.height, 1.55);
      // Body text is the system face on purpose.
      expect(theme.bodyLarge?.fontFamily, isNull);
      expect(theme.labelSmall?.fontSize, 11);
      // .12em at 11px, the kicker tracking.
      expect(theme.labelSmall?.letterSpacing, closeTo(1.32, 0.001));
    });

    test(
      'figures are serif with tabular numerals, so columns of figures line up',
      () {
        for (final style in [
          AppTextStyles.figureHero,
          AppTextStyles.statValue,
          AppTextStyles.figureSmall,
        ]) {
          expect(style.fontFamily, AppFonts.serif);
          expect(
            style.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
      },
    );

    test('the handwriting face is used for margin notes and nothing else', () {
      final hand = AppTextStyles.all
          .where((style) => style.fontFamily == AppFonts.hand)
          .toList();
      expect(hand, [AppTextStyles.marginNote]);
    });
  });

  group('platform surfaces', () {
    test('iOS is translucent and blurred, Android is not', () {
      expect(AppSurfaceTokens.ios.isGlass, isTrue);
      expect(AppSurfaceTokens.android.isGlass, isFalse);
      expect(AppSurfaceTokens.android.blurSigma, 0);
      expect(AppSurfaceTokens.ios.cardFill.a, lessThan(1.0));
      expect(AppSurfaceTokens.android.cardFill.a, 1.0);
    });

    // Android surfaces are flat paper divided by rules; only glass lifts.
    test('Android surfaces are flat, iOS glass carries a shadow', () {
      expect(AppSurfaceTokens.android.cardShadow, isEmpty);
      expect(AppSurfaceTokens.ios.cardShadow, isNotEmpty);
      expect(AppSurfaceTokens.android.cardFill, AppColors.ground);
    });

    test('lerp moves between the two without dropping a field', () {
      final mid = AppSurfaceTokens.ios.lerp(AppSurfaceTokens.android, 0.5);
      expect(mid.cardRadius, closeTo(16, 0.001));
      expect(mid.blurSigma, closeTo(5.5, 0.001));
      expect(mid.cardShadow, isNotEmpty);
    });
  });

  group('theme', () {
    // One paper on both platforms. A transparent iOS scaffold let a grey
    // through on device, so pages and paper-coloured bands disagreed.
    test('both platforms draw every page on the paper', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          AppTheme.light(platform).scaffoldBackgroundColor,
          AppColors.ground,
        );
      }
    });

    test('carries the surface tokens for the platform it was built for', () {
      expect(
        AppTheme.light(TargetPlatform.iOS).extension<AppSurfaceTokens>(),
        AppSurfaceTokens.ios,
      );
      expect(
        AppTheme.light(TargetPlatform.android).extension<AppSurfaceTokens>(),
        AppSurfaceTokens.android,
      );
    });
  });
}

extension on TextTheme {
  /// The slots the app declares, ignoring the ones Material fills in.
  List<TextStyle> get declaredStyles => [
    displaySmall,
    headlineSmall,
    titleLarge,
    titleMedium,
    bodyLarge,
    bodyMedium,
    bodySmall,
    labelSmall,
  ].whereType<TextStyle>().toList();
}
