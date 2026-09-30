import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// Paints the page every screen sits on.
///
/// This exists because the two platforms disagree about what a page *is*.
/// Android is a flat white sheet, which `scaffoldBackgroundColor` handles on
/// its own. iOS is a gradient, and a gradient is not a colour -- there is no
/// `ThemeData` slot that takes one. So [AppTheme.light] leaves the iOS
/// scaffold transparent and this fills in behind it.
///
/// It has to wrap the whole app rather than each screen: the tab bar floats
/// over the page, and a per-screen background would end at the screen's edge
/// and leave the bar sitting on nothing.
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({required this.child, super.key});

  final Widget child;

  /// Use as `MaterialApp.builder`, which is the one place that wraps the
  /// navigator without being rebuilt by it.
  static Widget builder(BuildContext context, Widget? child) {
    return AppPageBackground(child: child ?? const SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isCupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    if (!isCupertino) {
      return ColoredBox(color: AppColors.androidBackground, child: child);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.iosBackground),
      child: child,
    );
  }
}
