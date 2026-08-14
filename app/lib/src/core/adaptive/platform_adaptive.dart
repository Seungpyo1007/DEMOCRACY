import 'dart:ui' show lerpDouble;

import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

abstract final class PlatformAdaptiveRoute {
  static Page<T> page<T>({
    required BuildContext context,
    required LocalKey key,
    required Widget child,
  }) {
    if (_isCupertino(context)) {
      return CupertinoPage<T>(key: key, child: child);
    }
    return MaterialPage<T>(key: key, child: child);
  }
}

/// The screen title bar.
///
/// This is a builder rather than a widget because [PreferredSizeWidget] has to
/// report its height from a getter that runs without a [BuildContext], so a
/// wrapper widget cannot know which platform it is on when [Scaffold] asks.
/// Wrapping one anyway meant reporting Material's 56 on both, and a Cupertino
/// navigation bar is 44 -- every iOS screen started 12pt lower than the mockup.
///
/// Returning the platform's own bar hands that question back to the widget
/// that can actually answer it.
abstract final class PlatformAdaptiveAppBar {
  static PreferredSizeWidget of(
    BuildContext context, {
    required String title,
    Widget? trailing,
  }) {
    if (_isCupertino(context)) {
      return CupertinoNavigationBar(
        middle: Text(title),
        trailing: trailing,
        backgroundColor: AppColors.neutral100.withValues(alpha: 0.94),
      );
    }

    return AppBar(
      title: Text(title),
      actions: trailing == null ? null : [trailing],
    );
  }
}

class AdaptiveTabItem {
  const AdaptiveTabItem({
    required this.label,
    required this.icon,
    this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

class PlatformAdaptiveTabBar extends StatelessWidget {
  const PlatformAdaptiveTabBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.minimized = false,
    super.key,
  });

  /// The bar's visible surface, whatever it is made of.
  ///
  /// The material behind the strip changed once already -- an opaque Material
  /// became a glass container on iOS -- and a test that finds the surface by
  /// its widget type breaks on that change while the thing it is checking
  /// (does the bar hug its content and clear the edges) has not moved.
  static const surfaceKey = ValueKey('platform-adaptive-tab-bar-surface');

  final int currentIndex;
  final List<AdaptiveTabItem> items;
  final ValueChanged<int> onTap;

  /// Shrinks the capsule and drops the labels, matching the way the iOS 26
  /// tab bar contracts while the user is scrolling down.
  final bool minimized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTokens = theme.extension<AppSurfaceTokens>()!;

    // One layout on both platforms. NavigationBar and CupertinoTabBar both
    // stretch to the full width, and the shape this product wants is the
    // iOS 26 one: a capsule only as wide as its own items. The material
    // underneath does differ -- iOS gets real glass, Android an opaque
    // surface -- but that is [_FloatingBarFrame]'s business, not this one's.
    return _FloatingBarFrame(
      inset: surfaceTokens.navBarInset,
      surfaceTokens: surfaceTokens,
      // surfaceContainerLowest, not surfaceContainer: this scheme is seeded
      // monochrome, so the mid container roles collapse onto the page
      // background and the capsule stops reading as detached.
      color: theme.colorScheme.surfaceContainerLowest,
      child: _CapsuleTabStrip(
        currentIndex: currentIndex,
        items: items,
        onTap: onTap,
        minimized: minimized,
      ),
    );
  }
}

/// The destinations, with a selection capsule that slides between them.
///
/// The capsule sits behind the whole destination rather than behind its icon,
/// and it travels to the new index instead of reappearing there. Items are a
/// fixed width because a sliding indicator has to know where each one starts.
class _CapsuleTabStrip extends StatelessWidget {
  const _CapsuleTabStrip({
    required this.currentIndex,
    required this.items,
    required this.onTap,
    required this.minimized,
  });

  static const _duration = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;

  static const _expandedWidth = 64.0;
  static const _expandedHeight = 52.0;
  static const _minimizedWidth = 46.0;
  static const _minimizedHeight = 38.0;
  static const _padding = 6.0;

  /// The label has a fixed line height that cannot shrink with the capsule,
  /// so it has to be gone well before the capsule reaches its minimum.
  static const _labelFadeEnd = 0.35;

  final int currentIndex;
  final List<AdaptiveTabItem> items;
  final ValueChanged<int> onTap;
  final bool minimized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      duration: _duration,
      curve: _curve,
      tween: Tween(begin: 0, end: minimized ? 1 : 0),
      builder: (context, t, _) {
        final itemWidth = lerpDouble(_expandedWidth, _minimizedWidth, t)!;
        final itemHeight = lerpDouble(_expandedHeight, _minimizedHeight, t)!;
        final labelOpacity = (1 - t / _labelFadeEnd).clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.all(_padding),
          child: SizedBox(
            width: itemWidth * items.length,
            height: itemHeight,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: itemWidth * currentIndex,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colors.secondaryContainer,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      SizedBox(
                        width: itemWidth,
                        child: _CapsuleTabItem(
                          item: items[i],
                          selected: i == currentIndex,
                          onTap: () => onTap(i),
                          iconSize: lerpDouble(22, 20, t)!,
                          labelOpacity: labelOpacity,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One destination. Draws no selection surface of its own; the strip slides a
/// shared capsule behind it, so this only resolves foreground colours.
class _CapsuleTabItem extends StatelessWidget {
  const _CapsuleTabItem({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.iconSize,
    required this.labelOpacity,
  });

  final AdaptiveTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final double iconSize;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? (item.activeIcon ?? item.icon) : item.icon,
              size: iconSize,
              color: foreground,
            ),
            // Dropped from the tree once faded out, so it stops reserving the
            // height the shrinking capsule no longer has.
            if (labelOpacity > 0) ...[
              SizedBox(height: 3 * labelOpacity),
              Opacity(
                opacity: labelOpacity,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lifts a navigation bar off the bottom edge as a detached capsule.
///
/// [Center] lets the capsule take only the width its items need, which is the
/// part that makes it read as an iOS 26 tab bar rather than a bar with rounded
/// ends. [StadiumBorder] keeps the ends fully round at whatever height the bar
/// resolves to. The elevation is a real shadow on an opaque surface, so
/// nothing here depends on translucency or a Liquid Glass implementation.
class _FloatingBarFrame extends StatelessWidget {
  const _FloatingBarFrame({
    required this.inset,
    required this.surfaceTokens,
    required this.color,
    required this.child,
  });

  final double inset;
  final AppSurfaceTokens surfaceTokens;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The bar is the surface the guide most wants to be glass -- it floats
    // over content, so anything opaque behind it is content the user loses.
    // Only the material changes here; the strip inside keeps its own layout,
    // its sliding indicator and its scroll contract.
    final Widget surface = surfaceTokens.isGlass
        ? GlassContainer(
            key: PlatformAdaptiveTabBar.surfaceKey,
            padding: EdgeInsets.zero,
            // The guide gives the bar radius 30 outright. At the expanded
            // height that is a capsule; at the contracted one it stays a
            // capsule, because the strip never gets shorter than 60.
            shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.iosTabBar),
            child: child,
          )
        : Material(
            key: PlatformAdaptiveTabBar.surfaceKey,
            color: color,
            surfaceTintColor: Colors.transparent,
            shadowColor: AppColors.ink.withValues(alpha: 0.20),
            elevation: 3,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: child,
          );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
        child: Center(
          // The bottom slot hands down an unbounded height, so the frame must
          // take its height from the child rather than try to fill.
          heightFactor: 1,
          child: surface,
        ),
      ),
    );
  }
}

abstract final class PlatformAdaptiveDialog {
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = '확인',
    VoidCallback? onConfirmed,
  }) {
    void handleConfirmed(BuildContext dialogContext) {
      Navigator.of(dialogContext).pop();
      onConfirmed?.call();
    }

    if (_isCupertino(context)) {
      return showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => handleConfirmed(context),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => handleConfirmed(context),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

/// Touch feedback, which the two platforms scale differently.
///
/// iOS reserves its heavier impacts for events with consequence, so a tab
/// change and a filter change should not feel the same as a judgement landing.
/// Android's selection click is quiet enough that the guide asks for a medium
/// impact where iOS would use a light one.
abstract final class PlatformAdaptiveHaptics {
  /// Moving between things: tabs, segments, chart segments.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// A value being committed: a report filed, a rating submitted, a judgement
  /// shown as final.
  static Future<void> impact(BuildContext context) {
    return _isCupertino(context)
        ? HapticFeedback.lightImpact()
        : HapticFeedback.mediumImpact();
  }
}

/// The modal sheet the guide reaches for five times: address autocomplete,
/// the verification prompt, profile editing, review composing, and the sort
/// selector.
///
/// Android gets the drag handle and the 28dp top radius Material 3 specifies;
/// iOS gets its own rounded card. Both are the framework's sheet underneath,
/// so dismissal, scrolling and the back gesture keep working.
abstract final class PlatformAdaptiveSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = BorderRadius.vertical(
      top: Radius.circular(surface.sheetRadius),
    );

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: surface.isGlass ? AppColors.neutral100 : AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!surface.isGlass) const _DragHandle(),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x1),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.neutral300,
          borderRadius: BorderRadius.circular(AppRadii.androidProgress),
        ),
      ),
    );
  }
}

/// The busy indicator, so a Material spinner does not appear mid-iOS.
abstract final class PlatformAdaptiveProgress {
  static Widget circular(BuildContext context) {
    return _isCupertino(context)
        ? const CupertinoActivityIndicator()
        : const CircularProgressIndicator();
  }
}

abstract interface class PlatformAdaptiveAuth {
  /// Performs device/account reauthentication only.
  ///
  /// A successful result must never be treated as proof of residency.
  Future<bool> authenticate({required String reason});
}

bool _isCupertino(BuildContext context) {
  return _isCupertinoPlatform(Theme.of(context).platform);
}

bool _isCupertinoPlatform(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}
