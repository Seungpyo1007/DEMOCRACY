import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.navigationShell,
    super.key,
  });

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
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: PlatformAdaptiveTabBar(
        currentIndex: navigationShell.currentIndex,
        items: _items,
        onTap: (index) {
          PlatformAdaptiveHaptics.selection();
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

