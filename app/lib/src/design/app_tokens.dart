import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF201E1D);
  static const ground = Color(0xFFF3F2F2);
  static const signal = Color(0xFFEC3013);

  static const neutral100 = Color(0xFFF7F6F5);
  static const neutral200 = Color(0xFFE6E3E0);
  static const neutral400 = Color(0xFFB8B4B1);
  static const neutral600 = Color(0xFF706C69);
  static const neutral900 = ink;

  static const fulfilled = Color(0xFF3D9A63);
  static const inProgress = Color(0xFFC9922E);
  static const unfulfilled = neutral400;
  static const reversed = Color(0xFFA82310);
  static const systemError = Color(0xFFBA1A1A);

  static const iosBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
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
  static const screen = 20.0;
}

abstract final class AppRadii {
  static const iosCard = 20.0;
  static const iosButton = 26.0;
  static const iosTabBar = 30.0;
  static const androidCard = 12.0;
  static const androidChip = 8.0;
  static const androidButton = 24.0;
  static const androidSheet = 28.0;
  static const androidNavBar = 28.0;
}

/// Insets that lift the navigation bar off the screen edges.
///
/// The mockup floats the iOS tab bar with a 14dp margin. Android uses the
/// Material 3 container inset of 16dp.
abstract final class AppNavBarInsets {
  static const ios = 14.0;
  static const android = 16.0;
}

@immutable
class AppSurfaceTokens extends ThemeExtension<AppSurfaceTokens> {
  const AppSurfaceTokens({
    required this.cardRadius,
    required this.chipRadius,
    required this.buttonRadius,
    required this.sheetRadius,
    required this.navBarRadius,
    required this.navBarInset,
  });

  static const ios = AppSurfaceTokens(
    cardRadius: AppRadii.iosCard,
    chipRadius: AppRadii.iosCard,
    buttonRadius: AppRadii.iosButton,
    sheetRadius: AppRadii.iosCard,
    navBarRadius: AppRadii.iosTabBar,
    navBarInset: AppNavBarInsets.ios,
  );

  static const android = AppSurfaceTokens(
    cardRadius: AppRadii.androidCard,
    chipRadius: AppRadii.androidChip,
    buttonRadius: AppRadii.androidButton,
    sheetRadius: AppRadii.androidSheet,
    navBarRadius: AppRadii.androidNavBar,
    navBarInset: AppNavBarInsets.android,
  );

  final double cardRadius;
  final double chipRadius;
  final double buttonRadius;
  final double sheetRadius;
  final double navBarRadius;
  final double navBarInset;

  @override
  AppSurfaceTokens copyWith({
    double? cardRadius,
    double? chipRadius,
    double? buttonRadius,
    double? sheetRadius,
    double? navBarRadius,
    double? navBarInset,
  }) {
    return AppSurfaceTokens(
      cardRadius: cardRadius ?? this.cardRadius,
      chipRadius: chipRadius ?? this.chipRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      sheetRadius: sheetRadius ?? this.sheetRadius,
      navBarRadius: navBarRadius ?? this.navBarRadius,
      navBarInset: navBarInset ?? this.navBarInset,
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
      navBarRadius: _lerp(navBarRadius, other.navBarRadius, t),
      navBarInset: _lerp(navBarInset, other.navBarInset, t),
    );
  }

  static double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }
}

abstract final class AppTypography {
  static const _fallback = <String>['Pretendard'];

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
      letterSpacing: 0.88,
    ),
  );
}
