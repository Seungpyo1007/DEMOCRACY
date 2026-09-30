import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The iOS branch cannot be exercised on a device from a Windows workstation,
/// so these tests are the only check that it behaves like the Android one.
void main() {
  const items = [
    AdaptiveTabItem(label: '지역구', icon: Icons.location_on_outlined),
    AdaptiveTabItem(label: '역사', icon: Icons.menu_book_outlined),
    AdaptiveTabItem(label: '트래커', icon: Icons.bar_chart_outlined),
    AdaptiveTabItem(label: 'AI', icon: Icons.auto_awesome_outlined),
    AdaptiveTabItem(label: '커뮤니티', icon: Icons.chat_bubble_outline),
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

  // iOS: a capsule only as wide as its items, clear of every edge -- the
  // property that distinguishes the iOS 26 shape from a full-width bar with
  // rounded ends. Six items still have to fit a 390dp phone.
  testWidgets('iOS hugs its content and clears every edge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(TargetPlatform.iOS));

    final screen = tester.getRect(find.byType(MaterialApp));
    final capsule = tester.getRect(find.byType(PlatformAdaptiveTabBar));
    final surface = tester.getRect(
      find.byKey(PlatformAdaptiveTabBar.surfaceKey),
    );

    expect(surface.width, lessThan(capsule.width));
    expect(surface.bottom, lessThan(screen.bottom));
    expect(surface.left, greaterThan(screen.left));
    expect(surface.right, lessThan(screen.right));
  });

  // Android: edge to edge on the bottom, one pill that travels to the tab.
  testWidgets('Android spans the bottom edge with every destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(TargetPlatform.android));

    final screen = tester.getRect(find.byType(MaterialApp));
    final surface = tester.getRect(
      find.byKey(PlatformAdaptiveTabBar.surfaceKey),
    );
    expect(surface.width, screen.width);
    expect(surface.bottom, screen.bottom);
    expect(surface.height, greaterThanOrEqualTo(72));
    expect(find.byKey(const ValueKey('tab-indicator')), findsOneWidget);
  });

  testWidgets('Android slides the pill to the new tab and settles on it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(TargetPlatform.android));
    Rect pill() => tester.getRect(find.byKey(const ValueKey('tab-indicator')));
    final start = pill();

    await tester.pumpWidget(harness(TargetPlatform.android, currentIndex: 4));
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-travel the leading edge has run ahead: the pill is stretched.
    expect(pill().width, greaterThan(start.width));

    await tester.pumpAndSettle();
    final end = pill();
    expect(end.width, start.width);
    expect(end.center.dx, greaterThan(start.center.dx));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform reports the tapped destination', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(harness(platform, onTap: tapped.add));

      await tester.tap(find.text('커뮤니티'));
      await tester.pump();

      expect(tapped, [4]);
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
      return tester.getRect(find.byKey(PlatformAdaptiveTabBar.surfaceKey));
    }

    testWidgets('contracts the capsule and drops the labels', (tester) async {
      await tester.pumpWidget(harness(TargetPlatform.iOS));
      final expanded = surfaceOf(tester);
      expect(find.text('지역구'), findsOneWidget);

      await tester.pumpWidget(harness(TargetPlatform.iOS, minimized: true));
      await tester.pumpAndSettle();
      final contracted = surfaceOf(tester);

      expect(contracted.height, lessThan(expanded.height));
      expect(contracted.width, lessThan(expanded.width));
      expect(find.text('지역구'), findsNothing);
    });

    testWidgets('expands again when restored', (tester) async {
      await tester.pumpWidget(harness(TargetPlatform.iOS, minimized: true));
      await tester.pumpAndSettle();
      final contracted = surfaceOf(tester);

      await tester.pumpWidget(harness(TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(surfaceOf(tester).height, greaterThan(contracted.height));
      expect(find.text('지역구'), findsOneWidget);
    });

    testWidgets('stays tappable while contracted', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        harness(TargetPlatform.iOS, minimized: true, onTap: tapped.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.pump();

      expect(tapped, [5]);
    });

    // Material's bar does not contract on scroll, so Android ignores it.
    testWidgets('leaves the Android bar as it is', (tester) async {
      await tester.pumpWidget(harness(TargetPlatform.android));
      final expanded = surfaceOf(tester);

      await tester.pumpWidget(harness(TargetPlatform.android, minimized: true));
      await tester.pumpAndSettle();

      expect(surfaceOf(tester), expanded);
      expect(find.text('지역구'), findsOneWidget);
    });
  });
}
