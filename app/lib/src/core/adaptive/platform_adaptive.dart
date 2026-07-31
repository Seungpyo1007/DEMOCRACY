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
    if (_isCupertino(context)) {
      return CupertinoTabBar(
        currentIndex: currentIndex,
        activeColor: AppColors.signal,
        inactiveColor: AppColors.neutral600,
        onTap: onTap,
        items: [
          for (final item in items)
            BottomNavigationBarItem(
              icon: Icon(item.icon),
              activeIcon: Icon(item.activeIcon ?? item.icon),
              label: item.label,
            ),
        ],
      );
    }

    final theme = Theme.of(context);
    final surfaceTokens = theme.extension<AppSurfaceTokens>()!;
    final borderRadius = BorderRadius.circular(surfaceTokens.navBarRadius);

    // A detached bar: the Material 3 container roles carry the elevation, so
    // the surface stays fully opaque. No blur, no translucency.
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          surfaceTokens.navBarInset,
          0,
          surfaceTokens.navBarInset,
          surfaceTokens.navBarInset,
        ),
        child: Material(
          color: theme.colorScheme.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          shadowColor: AppColors.ink.withValues(alpha: 0.18),
          elevation: 3,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
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
