import 'package:flutter/material.dart';

/// The "pine archive" palette: sage paper, green-black ink, one pine accent.
///
/// It replaces the handoff's red-on-ground palette. The redesign reads like a
/// public record rather than a campaign, so the page is a cool paper tone and
/// almost everything is ink on it. Colour is spent in three places only -- the
/// primary action, the handwritten margin notes, and a reversed pledge -- and
/// nowhere else, which is what lets a reversal stand out.
///
/// Pine was chosen over the handoff's red partly for N-1: a saturated red or
/// orange reads as a party colour in Korea, and a muted green does not.
abstract final class AppColors {
  static const ink = Color(0xFF1B2220);

  /// Sage paper. Both platforms draw on it; see [androidBackground].
  static const ground = Color(0xFFEEF0EB);
  static const white = Color(0xFFFFFFFF);

  /// Pine. The primary action and nothing decorative. As data it means
  /// exactly one thing -- a reversed pledge -- and nothing else may borrow it.
  static const signal = accent700;

  // Neutral ramp: cool grey-greens, so the greys sit in the same family as
  // the paper instead of reading as dirt on it.
  static const neutral100 = Color(0xFFE3E7E0);
  static const neutral200 = Color(0xFFD9DDD6);
  static const neutral300 = Color(0xFFCDD3CC);
  static const neutral400 = Color(0xFFBEC5BD);
  static const neutral500 = Color(0xFF8A938E);
  static const neutral600 = Color(0xFF626B66);
  static const neutral700 = Color(0xFF4F5753);
  static const neutral800 = Color(0xFF39403D);
  static const neutral900 = Color(0xFF262D2A);

  // Accent ramp around pine. 700 is the accent itself: 6.5:1 on the paper and
  // 7.5:1 under white, so it is safe for body text and for a filled button.
  static const accent100 = Color(0xFFE4EDE9);
  static const accent200 = Color(0xFFCFE0D9);
  static const accent300 = Color(0xFFA9C6BA);
  static const accent400 = Color(0xFF7FA697);
  static const accent500 = Color(0xFF5E8A7C);
  static const accent600 = Color(0xFF3F6F61);
  static const accent700 = Color(0xFF2F5D50);
  static const accent800 = Color(0xFF234840);
  static const accent900 = Color(0xFF17302A);

  /// The 1px rule between rows. Sections are divided by a 2px [ink] rule
  /// instead, which is why this one is deliberately quiet.
  static const divider = neutral200;

  static const surface = neutral100;

  /// The stroke of a handwritten underline or arrow. Lighter than the accent
  /// because it is drawn, not read.
  static const handwriting = accent500;

  // Pledge status. Three of the four are a lightness ramp of ink, so they
  // stay distinct without hue -- and so the one that does carry hue, 번복, is
  // the thing the eye lands on. Icon and label always travel with the colour.
  static const fulfilled = ink;
  static const inProgress = neutral500;
  static const unfulfilled = neutral300;
  static const reversed = accent700;

  /// 「판정 전」 is not a verdict, so it sits outside the ink ramp: the
  /// quietest neutral, which no verdict uses.
  static const notJudged = neutral200;

  /// Text colour for each status, where the bar colour is too light to read.
  static const fulfilledText = ink;
  static const inProgressText = neutral700;
  static const unfulfilledText = neutral600;
  static const reversedText = accent700;
  static const notJudgedText = neutral600;

  // The chips tint their own background, so each status carries a pair.
  static const fulfilledChipBackground = ground;
  static const fulfilledChipForeground = fulfilledText;
  static const inProgressChipBackground = ground;
  static const inProgressChipForeground = inProgressText;
  static const unfulfilledChipBackground = ground;
  static const unfulfilledChipForeground = unfulfilledText;
  static const reversedChipBackground = accent100;
  static const reversedChipForeground = reversedText;

  /// The AI radar polygon fill: pine at 15%.
  static const radarFill = Color(0x262F5D50);

  static const systemError = Color(0xFFB3261E);

  /// Android draws on the same paper as iOS. The handoff put Android on white;
  /// the redesign is a single printed page on both, and only the chrome --
  /// tonal bars against glass -- tells the platforms apart.
  static const androidBackground = ground;

  /// The iOS page: the same flat paper as Android. It used to carry a faint
  /// vertical wash so drawn glass had something to refract, but real UIKit
  /// glass samples whatever is under it, and the wash made every paper-
  /// coloured band -- a pinned bar, a sheet -- a visibly different colour
  /// from the page it sat on.
  static const iosBackground = LinearGradient(colors: [ground, ground]);
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
    BoxShadow(color: Color(0x121B2220), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const glassMedium = <BoxShadow>[
    BoxShadow(color: Color(0x141B2220), blurRadius: 22, offset: Offset(0, 8)),
  ];
  static const glassLarge = <BoxShadow>[
    BoxShadow(color: Color(0x171B2220), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// The floating bars sit above content, so they carry the heaviest shadow.
  static const glassBar = <BoxShadow>[
    BoxShadow(color: Color(0x1F1B2220), blurRadius: 28, offset: Offset(0, 10)),
  ];

  static const ctaWide = <BoxShadow>[
    BoxShadow(color: Color(0x422F5D50), blurRadius: 22, offset: Offset(0, 8)),
  ];
  static const ctaInline = <BoxShadow>[
    BoxShadow(color: Color(0x382F5D50), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const androidFab = <BoxShadow>[
    BoxShadow(color: Color(0x291B2220), blurRadius: 10, offset: Offset(0, 3)),
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
    selectedChipFill: Color(0xE01B2220),
    selectedChipForeground: AppColors.white,
  );

  /// Opaque fills, no blur. Surfaces are the paper itself, separated by
  /// rules rather than by elevation; the bars take the one tonal step up.
  static const android = AppSurfaceTokens(
    cardRadius: AppRadii.androidCard,
    chipRadius: AppRadii.androidChip,
    buttonRadius: AppRadii.androidButton,
    sheetRadius: AppRadii.androidSheet,
    navBarInset: AppNavBarInsets.android,
    cardFill: AppColors.ground,
    cardBorder: AppColors.neutral200,
    cardShadow: AppElevation.none,
    barFill: AppColors.neutral100,
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

/// The bundled families. Both are OFL; the licence files sit beside the font
/// files under `assets/fonts/` and are registered with [LicenseRegistry] at
/// startup.
///
/// Gowun Batang is subset to KS X 1001's 2,350 syllables plus Latin, which
/// takes it from 16MB to under 3MB. A syllable outside that set falls through
/// to the system face rather than to tofu. Nanum Pen Script is shipped as
/// published: its licence reserves the name for unmodified files, so it is
/// not subset.
///
/// Body text has no family on purpose. It is the system face -- SF / Apple SD
/// Gothic Neo on iOS, Roboto / Noto Sans KR on Android -- which is the most
/// legible Korean UI face on each platform and costs nothing to ship.
abstract final class AppFonts {
  /// Titles, names and figures: the book-like voice of the redesign.
  static const serif = 'GowunBatang';

  /// Margin notes only. Never for data, never for anything a reader must
  /// parse to use the app.
  static const hand = 'NanumPenScript';
}

abstract final class AppTypography {
  /// The guide's floor. Nothing in the app may be declared smaller, however
  /// dense the mockup gets -- `app_tokens_test.dart` holds this.
  static const minFontSize = 10.0;

  static const textTheme = TextTheme(
    // iOS large title.
    displaySmall: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.68,
      height: 1.2,
    ),
    // Material's large top app bar title.
    headlineMedium: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    headlineSmall: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // Android top app bar title, sheet titles.
    titleLarge: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    titleMedium: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.55,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.55,
    ),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    // The kicker above every section: `01 현직 의원`.
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      // .12em at 11px.
      letterSpacing: 1.32,
    ),
  );
}

/// The roles the mockups use that Material's [TextTheme] has no slot for.
///
/// They are named for what they mark, not for their size, so a screen reads as
/// the design does. Figures are set in the serif with tabular numerals so a
/// number that counts up in place does not jitter sideways as it goes.
abstract final class AppTextStyles {
  static const _tabular = [FontFeature.tabularFigures()];

  static const onboardingHeadlineIos = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const onboardingHeadlineAndroid = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// The one number a screen is about: the tracker's overall rate.
  static const figureHero = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 112,
    fontWeight: FontWeight.w700,
    letterSpacing: -5.6,
    height: 0.95,
    fontFeatures: _tabular,
  );

  /// The community average.
  static const ratingDisplay = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    height: 1,
    fontFeatures: _tabular,
  );

  /// AI match score beside the #1 candidate.
  static const scoreDisplay = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    letterSpacing: -2.56,
    height: 0.9,
    fontFeatures: _tabular,
  );

  /// The dashboard's three-up figures.
  static const statValue = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 44,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.32,
    height: 1,
    fontFeatures: _tabular,
  );

  /// Figures at the end of a row: shares, counts, scores.
  static const figureSmall = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  /// The unit after a figure: `%`, `건`, `점`.
  static const figureUnit = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );

  /// Section kickers: `01 현직 의원`. Wide tracking, small, above a 2px rule.
  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    // .12em at 11px.
    letterSpacing: 1.32,
  );

  /// Small labels above a value: `감지된 지역구`, `내 지역구`.
  static const microLabel = sectionLabel;

  /// The label under a stat figure.
  static const statLabel = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  /// Row text: pledge titles, bill titles, timeline nodes.
  static const cardBody = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Long-form reading: AI summaries and resident reviews. Serif, loose.
  static const reading = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );

  /// Party tags and other outlined chips.
  static const tag = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

  /// Status labels and verification badges.
  static const badge = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// Source lines, disclaimers and footnotes.
  static const disclaimer = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Handwritten margin notes. Descriptive only, like everything else (N-5).
  static const marginNote = TextStyle(
    fontFamily: AppFonts.hand,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    height: 1.1,
  );

  /// Primary CTA label.
  static const cta = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  /// Secondary CTA and link rows.
  static const ctaSmall = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

  /// In-page tabs and the segmented control.
  static const tabLabel = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);

  /// Bottom navigation labels.
  static const navLabel = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);

  /// Every style declared above, for the floor test to walk.
  static const all = <TextStyle>[
    onboardingHeadlineIos,
    onboardingHeadlineAndroid,
    figureHero,
    ratingDisplay,
    scoreDisplay,
    statValue,
    figureSmall,
    figureUnit,
    sectionLabel,
    microLabel,
    statLabel,
    cardBody,
    reading,
    tag,
    badge,
    disclaimer,
    marginNote,
    cta,
    ctaSmall,
    tabLabel,
    navLabel,
  ];
}
