import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light(TargetPlatform platform) {
    final isCupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final surfaceTokens = isCupertino
        ? AppSurfaceTokens.ios
        : AppSurfaceTokens.android;
    final colorScheme =
        ColorScheme.fromSeed(
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
      scaffoldBackgroundColor: isCupertino
          ? AppColors.neutral100
          : AppColors.ground,
      textTheme: AppTypography.textTheme,
      // The bar floats as a capsule, so its surface comes from the wrapper in
      // PlatformAdaptiveTabBar rather than from here. Colours are Material 3
      // roles; 64 keeps the capsule compact while still clearing the 32dp
      // indicator plus a 12sp label.
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
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
