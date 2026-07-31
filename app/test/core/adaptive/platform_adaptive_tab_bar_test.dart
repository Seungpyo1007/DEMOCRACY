import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The iOS branch cannot be exercised on a device from a Windows workstation,
/// so these tests are the only check that it behaves like the Android one.
void main() {
  const items = [
    AdaptiveTabItem(label: '지역구', icon: Icons.location_on_outlined),
    AdaptiveTabItem(label: '트래커', icon: Icons.donut_large_outlined),
    AdaptiveTabItem(label: 'AI 분석', icon: Icons.auto_awesome_outlined),
    AdaptiveTabItem(label: '커뮤니티', icon: Icons.forum_outlined),
    AdaptiveTabItem(label: '개표', icon: Icons.map_outlined),
  ];

  Widget harness(
    TargetPlatform platform, {
    int currentIndex = 0,
    ValueChanged<int>? onTap,
    bool minimized = false,
  }) {
    return MaterialApp(
      theme: AppTheme.light(platform),
      home: Scaffold(
        bottomNavigationBar: PlatformAdaptiveTabBar(
          currentIndex: currentIndex,
          items: items,
          minimized: minimized,
          onTap: onTap ?? (_) {},
        ),
      ),
    );
  }

  // The bar takes only the width its items need instead of stretching edge to
  // edge. This is the property that distinguishes the intended shape from a
  // full-width bar with rounded ends, so it is worth asserting directly.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform hugs its content and clears every edge', (
      tester,
    ) async {
      await tester.pumpWidget(harness(platform));

      final screen = tester.getRect(find.byType(MaterialApp));
      final capsule = tester.getRect(find.byType(PlatformAdaptiveTabBar));
      final surface = tester.getRect(
        find
            .descendant(
              of: find.byType(PlatformAdaptiveTabBar),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(surface.width, lessThan(capsule.width));
      expect(surface.bottom, lessThan(screen.bottom));
      expect(surface.left, greaterThan(screen.left));
      expect(surface.right, lessThan(screen.right));
    });

    testWidgets('$platform reports the tapped destination', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(harness(platform, onTap: tapped.add));

      await tester.tap(find.text('커뮤니티'));
      await tester.pump();

      expect(tapped, [3]);
    });
  }

  testWidgets('every destination is labelled', (tester) async {
    await tester.pumpWidget(harness(TargetPlatform.android));

    for (final item in items) {
      expect(find.text(item.label), findsOneWidget);
    }
  });

  group('minimized', () {
    Rect surfaceOf(WidgetTester tester) {
      return tester.getRect(
        find
            .descendant(
              of: find.byType(PlatformAdaptiveTabBar),
              matching: find.byType(Material),
            )
            .first,
      );
    }

    testWidgets('contracts the capsule and drops the labels', (tester) async {
      await tester.pumpWidget(harness(TargetPlatform.android));
      final expanded = surfaceOf(tester);
      expect(find.text('지역구'), findsOneWidget);

      await tester.pumpWidget(harness(TargetPlatform.android, minimized: true));
      await tester.pumpAndSettle();
      final contracted = surfaceOf(tester);

      expect(contracted.height, lessThan(expanded.height));
      expect(contracted.width, lessThan(expanded.width));
      expect(find.text('지역구'), findsNothing);
    });

    testWidgets('expands again when restored', (tester) async {
      await tester.pumpWidget(harness(TargetPlatform.android, minimized: true));
      await tester.pumpAndSettle();
      final contracted = surfaceOf(tester);

      await tester.pumpWidget(harness(TargetPlatform.android));
      await tester.pumpAndSettle();

      expect(surfaceOf(tester).height, greaterThan(contracted.height));
      expect(find.text('지역구'), findsOneWidget);
    });

    testWidgets('stays tappable while contracted', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        harness(TargetPlatform.android, minimized: true, onTap: tapped.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.pump();

      expect(tapped, [4]);
    });
  });
}
