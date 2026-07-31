import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The iOS branch cannot be exercised on a device from a Windows workstation,
/// so these tests are the only check that it is wired up at all.
void main() {
  const items = [
    AdaptiveTabItem(label: '지역구', icon: Icons.location_on_outlined),
    AdaptiveTabItem(label: '개표', icon: Icons.map_outlined),
  ];

  Widget harness(TargetPlatform platform) {
    return MaterialApp(
      theme: AppTheme.light(platform),
      home: Scaffold(
        bottomNavigationBar: PlatformAdaptiveTabBar(
          currentIndex: 0,
          items: items,
          onTap: (_) {},
        ),
      ),
    );
  }

  testWidgets('iOS uses the Cupertino bar', (tester) async {
    await tester.pumpWidget(harness(TargetPlatform.iOS));

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Android uses the Material bar', (tester) async {
    await tester.pumpWidget(harness(TargetPlatform.android));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform lifts the bar off every screen edge', (
      tester,
    ) async {
      await tester.pumpWidget(harness(platform));

      final screen = tester.getRect(find.byType(MaterialApp));
      final bar = tester.getRect(
        find.byType(
          platform == TargetPlatform.iOS ? CupertinoTabBar : NavigationBar,
        ),
      );

      expect(bar.bottom, lessThan(screen.bottom));
      expect(bar.left, greaterThan(screen.left));
      expect(bar.right, lessThan(screen.right));
    });
  }
}
