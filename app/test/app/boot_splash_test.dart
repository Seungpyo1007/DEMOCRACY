import 'package:democracy/src/app/boot_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const app = MaterialApp(home: Scaffold(body: Text('홈')));

  testWidgets('draws the stamp at the centre, then gives way to the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BootSplash(child: app));

    final stamp = find.byKey(const ValueKey('boot-stamp'));
    expect(stamp, findsOneWidget);
    expect(tester.getCenter(stamp), const Offset(195, 422));

    // Nothing moves until the first frame is on screen.
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      (tester.widget<CustomPaint>(stamp).painter! as StampStrokes).ring,
      0,
    );
    await tester.pump();
    await tester.pump();

    // Mid-way the ring is drawn and the strokes are under way.
    await tester.pump(const Duration(milliseconds: 700));
    final mid = tester.widget<CustomPaint>(stamp).painter! as StampStrokes;
    expect(mid.ring, 1);
    expect(mid.stem, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(stamp, findsNothing);
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('is skipped with reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const BootSplash(child: app));
    expect(find.byKey(const ValueKey('boot-stamp')), findsNothing);
    expect(find.text('홈'), findsOneWidget);
  });
}
