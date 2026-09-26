import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  /// [nativeControls] declares that this process can host UIKit views. It
  /// defaults to off so that tests and goldens resolve to the Flutter
  /// controls; only the running app turns it on.
  static ThemeData light(
    TargetPlatform platform, {
    bool nativeControls = false,
  }) {
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
          onPrimary: AppColors.white,
          // Both platforms draw on the same paper. On iOS this is only the
          // fallback a Material surface resolves to underneath the glass.
          surface: AppColors.ground,
          // Material 3's tonal roles, stepped from the paper so the system
          // components -- bars, menus, search, sheets -- sit in its family.
          surfaceContainerLowest: AppColors.white,
          surfaceContainerLow: const Color(0xFFE8EBE5),
          surfaceContainer: AppColors.neutral100,
          surfaceContainerHigh: const Color(0xFFDDE2DA),
          surfaceContainerHighest: AppColors.neutral200,
          primaryContainer: AppColors.accent200,
          onPrimaryContainer: AppColors.accent900,
          secondaryContainer: AppColors.accent200,
          onSecondaryContainer: AppColors.accent900,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.neutral600,
          outline: AppColors.neutral500,
          outlineVariant: AppColors.neutral200,
          error: AppColors.systemError,
        );

    return ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: colorScheme,
      extensions: [
        surfaceTokens,
        nativeControls ? AppCapabilities.uiKit : AppCapabilities.none,
      ],
      // The paper on both platforms. iOS used to leave this transparent for
      // a gradient drawn behind the navigator; on a device that let a grey
      // show through between routes, so the page and every paper-coloured
      // band on it (a pinned bar, a sheet) came out two different colours.
      scaffoldBackgroundColor: AppColors.ground,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.neutral200,
      ),
      // The bar floats as a capsule, so its surface comes from the wrapper in
      // PlatformAdaptiveTabBar rather than from here. Colours are Material 3
      // roles; 64 keeps the capsule compact while still clearing the 32dp
      // indicator plus a 12sp label.
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: AppColors.neutral100,
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
            // Six destinations: a notch under Material's 24 keeps the bar
            // from reading as a row of glyphs.
            size: 22,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      // The Material 3 components, themed onto the paper rather than
      // restyled: they keep their own shapes, states and motion.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: AppTextStyles.cta,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: AppTextStyles.ctaSmall,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ground,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.signal,
        unselectedLabelColor: AppColors.neutral700,
        indicatorColor: AppColors.signal,
        dividerColor: AppColors.divider,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.ground,
        showDragHandle: true,
        dragHandleColor: AppColors.neutral700,
      ),
      searchBarTheme: const SearchBarThemeData(
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(AppColors.neutral100),
      ),
      chipTheme: const ChipThemeData(
        selectedColor: AppColors.accent200,
        side: BorderSide(color: AppColors.neutral500),
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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(surfaceTokens.cardRadius),
          ),
          borderSide: const BorderSide(color: AppColors.neutral400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(surfaceTokens.cardRadius),
          ),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
        ),
      ),
    );
  }
}
