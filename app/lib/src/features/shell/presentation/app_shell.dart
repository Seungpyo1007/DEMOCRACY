import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/features/shell/application/tab_accessory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  // iOS 26 tab bars draw filled symbols in both states and mark selection
  // with the tint and the glass bubble, so active and inactive share a glyph.
  static const _items = [
    AdaptiveTabItem(
      label: '지역구',
      sfSymbol: 'mappin.circle.fill',
      sfSymbolActive: 'mappin.circle.fill',
      icon: Icons.location_on_outlined,
      activeIcon: Icons.location_on,
    ),
    AdaptiveTabItem(
      label: '역사',
      sfSymbol: 'book.fill',
      sfSymbolActive: 'book.fill',
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book,
    ),
    AdaptiveTabItem(
      label: '트래커',
      sfSymbol: 'checkmark.circle.fill',
      sfSymbolActive: 'checkmark.circle.fill',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
    ),
    AdaptiveTabItem(
      label: 'AI',
      sfSymbol: 'sparkles',
      sfSymbolActive: 'sparkles',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
    ),
    AdaptiveTabItem(
      label: '커뮤니티',
      sfSymbol: 'bubble.left.fill',
      sfSymbolActive: 'bubble.left.fill',
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
    ),
    AdaptiveTabItem(
      label: '개표',
      sfSymbol: 'chart.bar.fill',
      sfSymbolActive: 'chart.bar.fill',
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
    ),
  ];

  /// Which branch can lend the tab bar its accessory action, by index.
  static const _slots = {2: TabSlot.tracker, 4: TabSlot.community};

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// How far the user has to travel in one direction before the bar reacts.
  ///
  /// Reacting to UserScrollNotification.direction instead looks correct while
  /// dragging but flips back on release: ending a drag emits a stray forward
  /// before idle, which reads as a scroll up and re-expands the bar. Requiring
  /// sustained travel ignores that jitter.
  static const _threshold = 28.0;

  bool _minimized = false;
  double _travel = 0;

  /// A new branch is showing its own scroll position, which starts at the top
  /// unless the reader left it somewhere else -- and either way it sends no
  /// notification for arriving. Without this the bar stayed contracted after a
  /// tab change, because the only thing that reopens it is a scroll to the top
  /// and nobody scrolled.
  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex !=
        oldWidget.navigationShell.currentIndex) {
      _travel = 0;
      _apply(minimized: false);
    }
  }

  /// Listening for notifications keeps the scroll coupling in the shell. The
  /// alternative, a ScrollController owned by every screen and threaded down
  /// here, would put shell concerns inside each feature.
  bool _handleScroll(ScrollUpdateNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final metrics = notification.metrics;

    // The bar is always open at the top, however the user got there.
    if (metrics.pixels <= metrics.minScrollExtent + _threshold) {
      _travel = 0;
      _apply(minimized: false);
      return false;
    }

    final delta = notification.scrollDelta ?? 0;
    if (_travel != 0 && delta.sign != _travel.sign) {
      _travel = 0;
    }
    _travel += delta;

    if (_travel > _threshold) {
      _apply(minimized: true);
    } else if (_travel < -_threshold) {
      _apply(minimized: false);
    }
    return false;
  }

  void _apply({required bool minimized}) {
    if (minimized != _minimized) {
      setState(() => _minimized = minimized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The page runs under the bar. On iOS the bar is Liquid Glass and the
      // content is meant to show through it; a fixed band behind it turned
      // the glass into a grey strip. Every page already ends with room for
      // the bar (EditorialScrollView.bottomPadding), so nothing is hidden at
      // rest.
      extendBody: true,
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: _handleScroll,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: Consumer(
        builder: (context, ref, _) {
          final index = widget.navigationShell.currentIndex;
          final slot = AppShell._slots[index];
          final lent = slot == null
              ? null
              : ref.watch(tabAccessoriesProvider)[slot];
          return PlatformAdaptiveTabBar(
            currentIndex: index,
            items: AppShell._items,
            minimized: _minimized,
            accessory: lent == null
                ? null
                : AdaptiveTabAccessory(
                    label: lent.label,
                    sfSymbol: lent.icon.sfSymbol,
                    onPressed: lent.onPressed,
                  ),
            onTap: (index) {
              PlatformAdaptiveHaptics.selection();
              widget.navigationShell.goBranch(
                index,
                initialLocation: index == widget.navigationShell.currentIndex,
              );
            },
          );
        },
      ),
    );
  }
}
