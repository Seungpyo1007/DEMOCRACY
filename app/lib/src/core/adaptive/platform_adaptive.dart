import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class PlatformAdaptiveAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const PlatformAdaptiveAppBar({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (_isCupertino(context)) {
      return CupertinoNavigationBar(
        middle: Text(title),
        trailing: trailing,
        backgroundColor: AppColors.neutral100.withValues(alpha: 0.94),
      );
    }

    return AppBar(
      title: Text(title),
      actions: trailing == null ? null : [trailing!],
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
    super.key,
  });

  final int currentIndex;
  final List<AdaptiveTabItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTokens = theme.extension<AppSurfaceTokens>()!;

    // One control on both platforms. NavigationBar and CupertinoTabBar both
    // stretch to the full width, and the shape this product wants is the
    // iOS 26 one: a capsule only as wide as its own items. Only the inset
    // still varies by platform.
    return _FloatingBarFrame(
      inset: surfaceTokens.navBarInset,
      // surfaceContainerLowest, not surfaceContainer: this scheme is seeded
      // monochrome, so the mid container roles collapse onto the page
      // background and the capsule stops reading as detached.
      color: theme.colorScheme.surfaceContainerLowest,
      child: _CapsuleTabStrip(
        currentIndex: currentIndex,
        items: items,
        onTap: onTap,
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
  });

  static const _itemWidth = 64.0;
  static const _itemHeight = 52.0;
  static const _padding = 6.0;

  final int currentIndex;
  final List<AdaptiveTabItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(_padding),
      child: SizedBox(
        width: _itemWidth * items.length,
        height: _itemHeight,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: _itemWidth * currentIndex,
              top: 0,
              bottom: 0,
              width: _itemWidth,
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
                    width: _itemWidth,
                    child: _CapsuleTabItem(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
  });

  final AdaptiveTabItem item;
  final bool selected;
  final VoidCallback onTap;

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
              size: 22,
              color: foreground,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: foreground,
              ),
            ),
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
    required this.color,
    required this.child,
  });

  final double inset;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
        child: Center(
          // The bottom slot hands down an unbounded height, so the frame must
          // take its height from the child rather than try to fill.
          heightFactor: 1,
          child: Material(
            color: color,
            surfaceTintColor: Colors.transparent,
            shadowColor: AppColors.ink.withValues(alpha: 0.20),
            elevation: 3,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
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

abstract final class PlatformAdaptiveHaptics {
  static Future<void> selection() => HapticFeedback.selectionClick();
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
