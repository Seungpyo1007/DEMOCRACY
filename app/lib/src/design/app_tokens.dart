import 'package:flutter/material.dart';

/// The palette from `design_handoff_democracy_app`.
///
/// Where the handoff README and the design-system CSS disagree, the CSS wins:
/// the README writes its status colours as `≈` approximations of `oklch()`
/// values, so it is the derived document, not the source.
abstract final class AppColors {
  static const ink = Color(0xFF201E1D);
  static const ground = Color(0xFFF3F2F2);
  static const white = Color(0xFFFFFFFF);

  /// Brand, CTA and active tab only. As data it means exactly one thing --
  /// a reversed pledge -- and nothing else may borrow it.
  static const signal = Color(0xFFEC3013);

  // Neutral ramp, verbatim from the design-system tokens.
  static const neutral100 = Color(0xFFF8F4F4);
  static const neutral200 = Color(0xFFEAE7E7);
  static const neutral300 = Color(0xFFD7D3D3);
  static const neutral400 = Color(0xFFBAB6B6);
  static const neutral500 = Color(0xFF9B9797);
  static const neutral600 = Color(0xFF7D7979);
  static const neutral700 = Color(0xFF605D5D);
  static const neutral800 = Color(0xFF444141);
  static const neutral900 = Color(0xFF2D2B2B);

  // Accent ramp. `accent-2` is deliberately absent: the design-system readme
  // says it is a machine-derived stand-in for the same role, so porting it
  // would invent a distinction the design does not make.
  static const accent100 = Color(0xFFFFF2EF);
  static const accent200 = Color(0xFFFFE0D9);
  static const accent300 = Color(0xFFFFC4B8);
  static const accent400 = Color(0xFFFF9783);
  static const accent500 = Color(0xFFFF563C);
  static const accent600 = Color(0xFFDD2B0F);
  static const accent700 = Color(0xFFAE1800);
  static const accent800 = Color(0xFF7C1405);
  static const accent900 = Color(0xFF4D170E);

  /// Ink at 40%, from `color-mix(in srgb, #201e1d 40%, transparent)`.
  static const divider = Color(0x66201E1D);

  static const surface = Color(0xFFEAE9E9);

  // Pledge status. Converted from the guide's oklch() values, which is why
  // these differ from the README's stated approximations.
  static const fulfilled = Color(0xFF249057); // oklch(0.58 0.13 155)
  static const inProgress = Color(0xFFCF9A35); // oklch(0.72 0.13 80)
  static const unfulfilled = neutral400;
  static const reversed = accent700;

  // The chips tint their own background, so each status carries a pair.
  static const fulfilledChipBackground = Color(0xFFD9EEDF);
  static const fulfilledChipForeground = Color(0xFF004922);
  static const inProgressChipBackground = Color(0xFFFDECD1);
  static const inProgressChipForeground = Color(0xFF694500);
  static const unfulfilledChipBackground = neutral200;
  static const unfulfilledChipForeground = neutral700;
  static const reversedChipBackground = accent100;
  static const reversedChipForeground = accent700;

  /// The AI radar polygon fill, `oklch(0.62 0.18 25 / .15)`.
  static const radarFill = Color(0x26DE4E4B);

  static const systemError = Color(0xFFBA1A1A);

  /// Android draws on white, not on Ground. Every Android mockup frame is
  /// `#fff` with cards separated by a neutral-300 border rather than by a
  /// tonal step, so the page has to be the lighter of the two.
  static const androidBackground = white;

  /// The iOS page. Glass only reads as glass over something with a gradient
  /// in it, which is why this is not a flat fill.
  static const iosBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    // 165deg in CSS, approximated on the vertical axis: the mockup's intent is
    // a top-to-bottom wash, and the 15deg tilt is not resolvable at 390dp.
    colors: [Color(0xFFEDEAE7), Color(0xFFF7F6F5), Color(0xFFE6E3E0)],
    stops: [0, 0.45, 1],
  );
}

abstract final class AppSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x12 = 48.0;

  /// Left and right page padding, fixed at 20 across every mockup.
  static const screen = 20.0;
}

abstract final class AppRadii {
  // iOS. The mockups use a small family of glass radii rather than one value:
  // the larger the surface, the rounder it is drawn.
  static const iosCardLarge = 22.0;
  static const iosCard = 20.0;
  static const iosCardSmall = 18.0;
  static const iosRow = 16.0;
  static const iosChip = 17.0;
  static const iosTabBar = 30.0;
  static const iosButton = 26.0;
  static const iosButtonWide = 27.0;
  static const iosButtonInline = 20.0;
  static const iosThumbnail = 12.0;
  static const iosPortrait = 14.0;

  // Android.
  static const androidCard = 12.0;
  static const androidChip = 8.0;
  static const androidButton = 24.0;
  static const androidFab = 16.0;
  static const androidSheet = 28.0;
  static const androidIndicator = 14.0;
  static const androidProgress = 2.0;
  static const androidThumbnail = 8.0;
}

/// Insets that lift the navigation bar off the screen edges.
///
/// The mockup floats the iOS tab bar with a 14dp margin. Android uses the
/// Material 3 container inset of 16dp. There is no matching radius token: the
/// bar is a capsule, so its corners follow its height via [StadiumBorder].
abstract final class AppNavBarInsets {
  static const ios = 14.0;
  static const android = 16.0;
}

/// Shadows, kept apart from radii because the two platforms use them for
/// opposite purposes: iOS to lift glass off the page, Android only under the
/// one element Material 3 actually elevates -- the FAB.
abstract final class AppElevation {
  static const glassSmall = <BoxShadow>[
    BoxShadow(color: Color(0x12201E1D), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const glassMedium = <BoxShadow>[
    BoxShadow(color: Color(0x14201E1D), blurRadius: 22, offset: Offset(0, 8)),
  ];
  static const glassLarge = <BoxShadow>[
    BoxShadow(color: Color(0x17201E1D), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// The floating bars sit above content, so they carry the heaviest shadow.
  static const glassBar = <BoxShadow>[
    BoxShadow(color: Color(0x24201E1D), blurRadius: 28, offset: Offset(0, 10)),
  ];

  static const ctaWide = <BoxShadow>[
    BoxShadow(color: Color(0x59EC3013), blurRadius: 22, offset: Offset(0, 8)),
  ];
  static const ctaInline = <BoxShadow>[
    BoxShadow(color: Color(0x4DEC3013), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const androidFab = <BoxShadow>[
    BoxShadow(color: Color(0x292D2B2B), blurRadius: 10, offset: Offset(0, 3)),
  ];

  static const none = <BoxShadow>[];
}

/// Everything a surface needs that differs by platform.
///
/// Colours live here rather than on [ColorScheme] because the difference is
/// not a Material role: iOS draws a translucent tint over a gradient page and
/// Android draws an opaque fill with a hairline border. One scheme cannot say
/// both.
@immutable
class AppSurfaceTokens extends ThemeExtension<AppSurfaceTokens> {
  const AppSurfaceTokens({
    required this.cardRadius,
    required this.chipRadius,
    required this.buttonRadius,
    required this.sheetRadius,
    required this.navBarInset,
    required this.cardFill,
    required this.cardBorder,
    required this.cardShadow,
    required this.barFill,
    required this.barBorder,
    required this.barShadow,
    required this.blurSigma,
    required this.selectedChipFill,
    required this.selectedChipForeground,
  });

  /// Translucent fills over the gradient page, blurred behind. The border is
  /// a white highlight rather than a dark hairline -- that is what reads as a
  /// lit edge instead of an outline.
  static const ios = AppSurfaceTokens(
    cardRadius: AppRadii.iosCard,
    chipRadius: AppRadii.iosChip,
    buttonRadius: AppRadii.iosButton,
    sheetRadius: AppRadii.iosCard,
    navBarInset: AppNavBarInsets.ios,
    cardFill: Color(0x99FFFFFF),
    cardBorder: Color(0xCCFFFFFF),
    cardShadow: AppElevation.glassLarge,
    barFill: Color(0x8CFFFFFF),
    barBorder: Color(0xCCFFFFFF),
    barShadow: AppElevation.glassBar,
    blurSigma: 11,
    selectedChipFill: Color(0xE0201E1D),
    selectedChipForeground: AppColors.white,
  );

  /// Opaque fills, no blur. Cards are white on white and separated by the
  /// border alone, so the border is load-bearing here in a way it is not on
  /// iOS.
  static const android = AppSurfaceTokens(
    cardRadius: AppRadii.androidCard,
    chipRadius: AppRadii.androidChip,
    buttonRadius: AppRadii.androidButton,
    sheetRadius: AppRadii.androidSheet,
    navBarInset: AppNavBarInsets.android,
    cardFill: AppColors.white,
    cardBorder: AppColors.neutral300,
    cardShadow: AppElevation.none,
    barFill: AppColors.white,
    barBorder: AppColors.neutral200,
    barShadow: AppElevation.none,
    blurSigma: 0,
    selectedChipFill: AppColors.ink,
    selectedChipForeground: AppColors.white,
  );

  final double cardRadius;
  final double chipRadius;
  final double buttonRadius;
  final double sheetRadius;
  final double navBarInset;

  final Color cardFill;
  final Color cardBorder;
  final List<BoxShadow> cardShadow;

  final Color barFill;
  final Color barBorder;
  final List<BoxShadow> barShadow;

  /// Zero on Android, which is how a caller knows not to pay for a
  /// [BackdropFilter] it would not see.
  final double blurSigma;

  final Color selectedChipFill;
  final Color selectedChipForeground;

  bool get isGlass => blurSigma > 0;

  @override
  AppSurfaceTokens copyWith({
    double? cardRadius,
    double? chipRadius,
    double? buttonRadius,
    double? sheetRadius,
    double? navBarInset,
    Color? cardFill,
    Color? cardBorder,
    List<BoxShadow>? cardShadow,
    Color? barFill,
    Color? barBorder,
    List<BoxShadow>? barShadow,
    double? blurSigma,
    Color? selectedChipFill,
    Color? selectedChipForeground,
  }) {
    return AppSurfaceTokens(
      cardRadius: cardRadius ?? this.cardRadius,
      chipRadius: chipRadius ?? this.chipRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      sheetRadius: sheetRadius ?? this.sheetRadius,
      navBarInset: navBarInset ?? this.navBarInset,
      cardFill: cardFill ?? this.cardFill,
      cardBorder: cardBorder ?? this.cardBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      barFill: barFill ?? this.barFill,
      barBorder: barBorder ?? this.barBorder,
      barShadow: barShadow ?? this.barShadow,
      blurSigma: blurSigma ?? this.blurSigma,
      selectedChipFill: selectedChipFill ?? this.selectedChipFill,
      selectedChipForeground:
          selectedChipForeground ?? this.selectedChipForeground,
    );
  }

  @override
  AppSurfaceTokens lerp(
    covariant ThemeExtension<AppSurfaceTokens>? other,
    double t,
  ) {
    if (other is! AppSurfaceTokens) {
      return this;
    }

    return AppSurfaceTokens(
      cardRadius: _lerp(cardRadius, other.cardRadius, t),
      chipRadius: _lerp(chipRadius, other.chipRadius, t),
      buttonRadius: _lerp(buttonRadius, other.buttonRadius, t),
      sheetRadius: _lerp(sheetRadius, other.sheetRadius, t),
      navBarInset: _lerp(navBarInset, other.navBarInset, t),
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      barFill: Color.lerp(barFill, other.barFill, t)!,
      barBorder: Color.lerp(barBorder, other.barBorder, t)!,
      barShadow: BoxShadow.lerpList(barShadow, other.barShadow, t)!,
      blurSigma: _lerp(blurSigma, other.blurSigma, t),
      selectedChipFill: Color.lerp(
        selectedChipFill,
        other.selectedChipFill,
        t,
      )!,
      selectedChipForeground: Color.lerp(
        selectedChipForeground,
        other.selectedChipForeground,
        t,
      )!,
    );
  }

  static double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }
}

/// What the process this build is running in can actually do.
///
/// Separate from [AppSurfaceTokens] because these are not design decisions.
/// Native controls are UIKit views embedded through a platform view, and a
/// platform view draws nothing under `flutter test` -- so a theme built for
/// iOS in a test must still resolve to the Flutter controls, or every widget
/// test and golden covering a switch would assert against an empty rectangle.
///
/// Defaults to off, and only [DemocracyApp] turns it on, on a real iOS
/// process. Anything that reads this is claiming "I have a native equivalent",
/// not "I look different on iOS" -- the latter is a surface token.
@immutable
class AppCapabilities extends ThemeExtension<AppCapabilities> {
  const AppCapabilities({required this.nativeControls});

  static const none = AppCapabilities(nativeControls: false);
  static const uiKit = AppCapabilities(nativeControls: true);

  final bool nativeControls;

  @override
  AppCapabilities copyWith({bool? nativeControls}) {
    return AppCapabilities(
      nativeControls: nativeControls ?? this.nativeControls,
    );
  }

  @override
  AppCapabilities lerp(
    covariant ThemeExtension<AppCapabilities>? other,
    double t,
  ) {
    // A capability is present or it is not; there is no halfway.
    return t < 0.5 ? this : (other is AppCapabilities ? other : this);
  }
}

abstract final class AppTypography {
  static const _fallback = <String>['Pretendard'];

  /// The guide's floor. Nothing in the app may be declared smaller, however
  /// dense the mockup gets -- `app_tokens_test.dart` holds this.
  static const minFontSize = 10.0;

  static const textTheme = TextTheme(
    displaySmall: TextStyle(
      fontFamily: 'Archivo',
      fontFamilyFallback: _fallback,
      fontSize: 28,
      fontWeight: FontWeight.w800,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Archivo',
      fontFamilyFallback: _fallback,
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Archivo',
      fontFamilyFallback: _fallback,
      fontSize: 19,
      fontWeight: FontWeight.w800,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Archivo',
      fontFamilyFallback: _fallback,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: TextStyle(
      fontFamilyFallback: _fallback,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.55,
    ),
    bodyMedium: TextStyle(
      fontFamilyFallback: _fallback,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.55,
    ),
    bodySmall: TextStyle(
      fontFamilyFallback: _fallback,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Archivo',
      fontFamilyFallback: _fallback,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      // .08em at 11px.
      letterSpacing: 0.88,
    ),
  );
}

/// The roles the mockups use that Material's [TextTheme] has no slot for.
///
/// They are named for what they mark, not for their size, so a screen reads as
/// the design does. Sizes below 12 are the guide's own -- it goes down to 9 for
/// tags and 10 for stat labels, and stops there.
abstract final class AppTextStyles {
  static const _fallback = <String>['Pretendard'];
  static const _heading = 'Archivo';

  /// Onboarding headline. iOS breaks it over two lines at 26; Android sets it
  /// at 24 on one.
  static const onboardingHeadlineIos = TextStyle(
    fontFamily: _heading,
    fontFamilyFallback: _fallback,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );
  static const onboardingHeadlineAndroid = TextStyle(
    fontFamily: _heading,
    fontFamilyFallback: _fallback,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  /// The community average, the largest number in the app.
  static const ratingDisplay = TextStyle(
    fontFamily: _heading,
    fontFamilyFallback: _fallback,
    fontSize: 30,
    fontWeight: FontWeight.w800,
  );

  /// AI match score in the rank header.
  static const scoreDisplay = TextStyle(
    fontFamily: _heading,
    fontFamilyFallback: _fallback,
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );

  /// The dashboard's three-up figures and the donut centre.
  static const statValue = TextStyle(
    fontFamily: _heading,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  /// Section headings: `현직 의원`, `카테고리별 이행률`. Wider tracking than
  /// [TextTheme.labelSmall], which is the data label.
  static const sectionLabel = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    // .1em at 11px.
    letterSpacing: 1.1,
  );

  /// Small all-caps labels above a value: `감지된 지역구`, `내 지역구`.
  static const microLabel = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    // .1em at 10px.
    letterSpacing: 1,
  );

  /// The label under a stat figure.
  static const statLabel = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w400,
  );

  /// Body inside a card: pledge rows, review bodies, timeline nodes.
  static const cardBody = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// Party tags and other chips that sit inside a dense row.
  static const tag = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    // .06em at 10px.
    letterSpacing: 0.6,
  );

  /// Status chips and verification badges.
  static const badge = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w700,
  );

  /// Disclaimers and footnotes. The guide sets these at 10.5; rounded up to
  /// the 10sp floor's nearest legible step rather than down.
  static const disclaimer = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Primary CTA label.
  static const cta = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  /// Secondary CTA and in-card tab labels.
  static const ctaSmall = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// Tab strip inside a card, and the segmented control.
  static const tabLabel = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Bottom navigation labels.
  static const navLabel = TextStyle(
    fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  /// Every style declared above, for the floor test to walk.
  static const all = <TextStyle>[
    onboardingHeadlineIos,
    onboardingHeadlineAndroid,
    ratingDisplay,
    scoreDisplay,
    statValue,
    sectionLabel,
    microLabel,
    statLabel,
    cardBody,
    tag,
    badge,
    disclaimer,
    cta,
    ctaSmall,
    tabLabel,
    navLabel,
  ];
}
