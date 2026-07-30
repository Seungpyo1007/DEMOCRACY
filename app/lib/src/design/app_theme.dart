import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light(TargetPlatform platform) {
    final isCupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final surfaceTokens =
        isCupertino ? AppSurfaceTokens.ios : AppSurfaceTokens.android;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    ).copyWith(
      primary: AppColors.signal,
      onPrimary: Colors.white,
      surface: isCupertino ? AppColors.neutral100 : AppColors.ground,
      onSurface: AppColors.ink,
      outline: AppColors.neutral400,
      error: AppColors.systemError,
    );

    return ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: colorScheme,
      extensions: [surfaceTokens],
      scaffoldBackgroundColor:
          isCupertino ? AppColors.neutral100 : AppColors.ground,
      textTheme: AppTypography.textTheme,
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: AppColors.neutral100,
        indicatorColor: AppColors.signal.withValues(alpha: 0.12),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.signal,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(surfaceTokens.cardRadius),
          ),
          borderSide: const BorderSide(color: AppColors.neutral400),
        ),
      ),
    );
  }
}
