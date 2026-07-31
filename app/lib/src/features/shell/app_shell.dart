import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  static const _items = [
    AdaptiveTabItem(
      label: '지역구',
      icon: Icons.location_on_outlined,
      activeIcon: Icons.location_on,
    ),
    AdaptiveTabItem(
      label: '트래커',
      icon: Icons.donut_large_outlined,
      activeIcon: Icons.donut_large,
    ),
    AdaptiveTabItem(
      label: 'AI 분석',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
    ),
    AdaptiveTabItem(
      label: '커뮤니티',
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum,
    ),
    AdaptiveTabItem(
      label: '개표',
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
    ),
  ];

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
      // Deliberately not extendBody. The bar is opaque, so letting content
      // slide under it would only hide it, and every scrollable screen would
      // then need its own bottom padding to compensate.
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: _handleScroll,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: PlatformAdaptiveTabBar(
        currentIndex: widget.navigationShell.currentIndex,
        items: AppShell._items,
        minimized: _minimized,
        onTap: (index) {
          PlatformAdaptiveHaptics.selection();
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}
