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
    // The README states these as `≈` approximations of oklch() values. The
    // converted values are what the design actually specifies, and they are
    // visibly different -- #249057 against the README's #3D9A63.
    test('come from the oklch source, not the README approximations', () {
      expect(AppColors.fulfilled, const Color(0xFF249057));
      expect(AppColors.inProgress, const Color(0xFFCF9A35));
    });

    test('미이행 is neutral 400, the value the guide names', () {
      expect(AppColors.unfulfilled, AppColors.neutral400);
    });

    // Signal is the brand colour. The guide allows it back into data for
    // exactly one meaning, and a second borrower would make the brand read as
    // a judgement.
    test('번복 is the only status allowed to reuse the accent', () {
      expect(AppColors.reversed, AppColors.accent700);
      for (final other in [
        AppColors.fulfilled,
        AppColors.inProgress,
        AppColors.unfulfilled,
      ]) {
        expect(other, isNot(AppColors.signal));
        expect(other, isNot(AppColors.accent700));
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

    test('the named scale matches the guide', () {
      final theme = AppTypography.textTheme;
      expect(theme.displaySmall?.fontSize, 28);
      expect(theme.headlineSmall?.fontSize, 22);
      expect(theme.titleLarge?.fontSize, 19);
      expect(theme.titleMedium?.fontSize, 17);
      expect(theme.bodyLarge?.fontSize, 15);
      expect(theme.bodyLarge?.height, 1.55);
      expect(theme.bodySmall?.fontSize, 12);
      expect(theme.labelSmall?.fontSize, 11);
      // .08em at 11px, the guide's data-label tracking.
      expect(theme.labelSmall?.letterSpacing, closeTo(0.88, 0.001));
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

    // Android cards are white on a white page, so the border is the only
    // thing separating them. iOS can afford a shadow instead.
    test('Android separates cards with a border, iOS with a shadow', () {
      expect(AppSurfaceTokens.android.cardShadow, isEmpty);
      expect(AppSurfaceTokens.ios.cardShadow, isNotEmpty);
      expect(AppSurfaceTokens.android.cardBorder, AppColors.neutral300);
    });

    test('lerp moves between the two without dropping a field', () {
      final mid = AppSurfaceTokens.ios.lerp(AppSurfaceTokens.android, 0.5);
      expect(mid.cardRadius, closeTo(16, 0.001));
      expect(mid.blurSigma, closeTo(5.5, 0.001));
      expect(mid.cardShadow, isNotEmpty);
    });
  });

  group('theme', () {
    test('Android draws on white, iOS leaves the page to the gradient', () {
      expect(
        AppTheme.light(TargetPlatform.android).scaffoldBackgroundColor,
        AppColors.androidBackground,
      );
      expect(
        AppTheme.light(TargetPlatform.iOS).scaffoldBackgroundColor,
        Colors.transparent,
      );
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
