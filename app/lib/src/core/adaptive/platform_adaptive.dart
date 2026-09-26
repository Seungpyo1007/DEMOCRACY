import 'dart:ui' show lerpDouble;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show LiquidGlassAlert, LiquidGlassAlertAction, NativeLiquidGlassUtils;

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
    this.sfSymbol,
    this.sfSymbolActive,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;

  /// The SF Symbol the native iOS tab bar draws. Without one the item falls
  /// back to the Material glyph, which UIKit renders as an image.
  final String? sfSymbol;
  final String? sfSymbolActive;
}

/// The tab the native bar last showed, kept so the bar has something valid
/// to show while a destination outside it is current.
int _lastTab = 0;

/// Point size for the native tab glyphs. Set on each symbol: the bar's own
/// `iconSize` does not reach SF Symbols, which is why the first pass drew
/// them at the system's large default.
const _nativeIconSize = 15.0;

CNTabBarItem _nativeItem(AdaptiveTabItem item) {
  return CNTabBarItem(
    label: item.label,
    icon: item.sfSymbol == null
        ? null
        : CNSymbol(item.sfSymbol!, size: _nativeIconSize),
    activeIcon: item.sfSymbolActive == null
        ? null
        : CNSymbol(item.sfSymbolActive!, size: _nativeIconSize),
    customIcon: item.sfSymbol == null ? item.icon : null,
    activeCustomIcon: item.sfSymbol == null ? item.activeIcon : null,
  );
}

/// A primary action the current tab lends to the native iOS tab bar's round
/// accessory, in place of the destination that normally sits there.
@immutable
class AdaptiveTabAccessory {
  const AdaptiveTabAccessory({
    required this.label,
    required this.sfSymbol,
    required this.onPressed,
  });

  final String label;
  final String sfSymbol;
  final VoidCallback onPressed;
}

class PlatformAdaptiveTabBar extends StatelessWidget {
  const PlatformAdaptiveTabBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.minimized = false,
    this.accessory,
    super.key,
  });

  /// Native iOS only: while set, the round button beside the bar is this
  /// action instead of the sixth destination, and morphs between the two as
  /// the reader changes tab. Pages that lend one draw no floating button of
  /// their own there.
  final AdaptiveTabAccessory? accessory;

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

  Widget _extraButton(AdaptiveTabItem item, int index) {
    final selected = currentIndex == index;
    return Semantics(
      key: ValueKey('tab-extra-$index'),
      button: true,
      selected: selected,
      label: item.label,
      child: CNButton.icon(
        icon: CNSymbol(item.sfSymbol ?? 'circle', size: _nativeIconSize),
        tint: selected ? AppColors.signal : AppColors.ink,
        config: const CNButtonConfig(style: CNButtonStyle.glass, minHeight: 60),
        onPressed: () => onTap(index),
      ),
    );
  }

  Widget _accessoryButton(AdaptiveTabAccessory action) {
    return Semantics(
      key: ValueKey('tab-accessory-${action.label}'),
      button: true,
      label: action.label,
      child: CNButton.icon(
        icon: CNSymbol(action.sfSymbol, size: _nativeIconSize + 2),
        tint: AppColors.signal,
        config: const CNButtonConfig(
          style: CNButtonStyle.prominentGlass,
          minHeight: 60,
        ),
        onPressed: action.onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTokens = theme.extension<AppSurfaceTokens>()!;

    // One layout on both platforms. NavigationBar and CupertinoTabBar both
    // stretch to the full width, and the shape this product wants is the
    // iOS 26 one: a capsule only as wide as its own items. The material
    // underneath does differ -- iOS gets real glass, Android an opaque
    // surface -- but that is [_FloatingBarFrame]'s business, not this one's.
    // Android: Material 3's navigation bar, the platform's own control.
    if (!surfaceTokens.isGlass) {
      return NavigationBar(
        key: PlatformAdaptiveTabBar.surfaceKey,
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.activeIcon ?? item.icon),
              label: item.label,
            ),
        ],
      );
    }

    // iOS 26: the system UITabBar, Liquid Glass and all, in the widget tree
    // so the shell keeps owning the index. It does not minimize on scroll --
    // only the full UITabBarController takeover can, and that would break
    // per-tab state (see HANDOFF). [minimized] is ignored here.
    //
    // UITabBar takes five items at most (the package asserts it, and UIKit
    // squeezes a sixth into a bar built for five). Past five, the extra
    // destinations float beside the bar as their own glass buttons -- the
    // place iOS 26 puts its separate search tab.
    if (theme.extension<AppCapabilities>()?.nativeControls ?? false) {
      const maxTabs = 5;
      final tabs = items.take(maxTabs).toList();
      final extras = items.skip(maxTabs).toList();
      final inTabs = currentIndex < maxTabs;
      // No SafeArea and no bottom padding: UITabBar lays itself out around
      // the home indicator, and its intrinsic height already includes it.
      // Wrapping it doubled the space -- the bar sat on a 139pt block.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        child: Row(
          children: [
            Expanded(
              child: CNTabBar(
                key: PlatformAdaptiveTabBar.surfaceKey,
                // UIKit cannot show "nothing selected"; while an extra is
                // current the bar keeps its last tab and the extra lights
                // up instead.
                currentIndex: inTabs ? currentIndex : _lastTab,
                onTap: (index) {
                  _lastTab = index;
                  onTap(index);
                },
                tint: AppColors.signal,
                items: [for (final item in tabs) _nativeItem(item)],
              ),
            ),
            for (var i = 0; i < extras.length; i++)
              Padding(
                // Lifted to sit on the bar's capsule, which UIKit draws
                // above the home indicator rather than centred in the view.
                padding: const EdgeInsets.only(left: AppSpacing.x1, bottom: 8),
                child: SizedBox.square(
                  dimension: 60,
                  child: _AccessorySwitcher(
                    child: i == 0 && accessory != null
                        ? _accessoryButton(accessory!)
                        : _extraButton(extras[i], maxTabs + i),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Where UIKit is unavailable (tests, goldens, older systems): the drawn
    // capsule, same contract.

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

  /// Six destinations have to fit a 390dp screen with the capsule's inset,
  /// so items are 56 wide rather than the 64 five of them could have.
  static const _expandedWidth = 56.0;
  static const _expandedHeight = 52.0;
  static const _minimizedWidth = 44.0;
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
                          iconSize: lerpDouble(20, 18, t)!,
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

  /// How far the label may grow before the fixed capsule would clip it.
  static const _maxLabelScale = 1.3;

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
                // The capsule's height is fixed by the guide, so the label
                // cannot grow without clipping: at 2x it overflowed. Capping
                // the label rather than the bar keeps the shape the design
                // specifies while everything else in the app still scales --
                // the same trade Material's own NavigationBar makes.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _maxLabelScale,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
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

/// A short confirmation that something happened: `평가를 올렸습니다`.
///
/// Android shows Material's snackbar, which is its system pattern for this.
/// iOS has no snackbar -- a Material bar sliding up on an iPhone reads as a
/// foreign app -- so it shows the system alert with a single 확인.
abstract final class PlatformAdaptiveNotice {
  static Future<void> show(
    BuildContext context, {
    required String message,
    String? title,
  }) async {
    if (_isCupertino(context)) {
      return PlatformAdaptiveDialog.show(
        context: context,
        title: title ?? '',
        message: message,
      );
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

abstract final class PlatformAdaptiveDialog {
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = '확인',
    VoidCallback? onConfirmed,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    void handleConfirmed(BuildContext dialogContext) {
      Navigator.of(dialogContext).pop();
      onConfirmed?.call();
    }

    // A second, non-default action placed before the confirm button, which is
    // where both platforms put the less emphatic choice.
    void handleSecondary(BuildContext dialogContext) {
      Navigator.of(dialogContext).pop();
      onSecondary?.call();
    }

    // iOS with UIKit: the system alert itself (UIAlertController, Liquid
    // Glass on iOS 26). The Cupertino dialog below is Flutter's drawing of
    // one, kept for tests and systems without the native presenter.
    if (_isCupertino(context) &&
        (Theme.of(context).extension<AppCapabilities>()?.nativeControls ??
            false) &&
        NativeLiquidGlassUtils.supportsLiquidGlass) {
      return LiquidGlassAlert.show(
        context: context,
        title: title,
        message: message,
        actions: [
          if (secondaryLabel != null)
            LiquidGlassAlertAction(id: 'secondary', title: secondaryLabel),
          LiquidGlassAlertAction(id: 'confirm', title: confirmLabel),
        ],
      ).then((choice) {
        if (choice == 'secondary') {
          onSecondary?.call();
        } else if (choice == 'confirm') {
          onConfirmed?.call();
        }
      });
    }

    if (_isCupertino(context)) {
      return showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (secondaryLabel != null)
              CupertinoDialogAction(
                onPressed: () => handleSecondary(context),
                child: Text(secondaryLabel),
              ),
            CupertinoDialogAction(
              isDefaultAction: secondaryLabel != null,
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
          if (secondaryLabel != null)
            TextButton(
              onPressed: () => handleSecondary(context),
              child: Text(secondaryLabel),
            ),
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
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurfaceTokens>()!;

    // iOS with UIKit: the system sheet presentation, through the package's
    // wrapper so the native tab bar and buttons hide beneath it rather than
    // drawing through it.
    if (surface.isGlass &&
        (theme.extension<AppCapabilities>()?.nativeControls ?? false)) {
      return CNBottomSheet.showCupertino<T>(
        context: context,
        pageBuilder: (context) => Material(
          color: AppColors.ground,
          child: SafeArea(top: false, child: builder(context)),
        ),
      );
    }

    // Android: Material 3's modal bottom sheet with its drag handle (from
    // the theme). The iOS stand-in shares it, on the same paper.
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(surface.sheetRadius),
        ),
      ),
      builder: (context) => CNSheetGeometryProbe(
        child: SafeArea(top: false, child: builder(context)),
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

/// The morph between the accessory's two lives -- a destination in glass and
/// the tab's action in pine: the old one shrinks away as the new one grows
/// in, in the same spot, so it reads as one button changing role.
class _AccessorySwitcher extends StatelessWidget {
  const _AccessorySwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 360),
      switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
