import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  double opacityOf(WidgetTester tester) {
    return tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(InkLoadingSection),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
  }

  CustomPaint paintOf(WidgetTester tester, Type type) {
    return tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(type),
        matching: find.byType(CustomPaint),
      ),
    );
  }

  testWidgets('shows nothing for a load shorter than the delay', (
    tester,
  ) async {
    await pump(tester, const InkLoadingSection());

    await tester.pump(appearDelay - const Duration(milliseconds: 10));
    expect(opacityOf(tester), 0);

    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
  });

  testWidgets('is read out as loading', (tester) async {
    await pump(tester, const InkRingIndicator());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
  });

  // Tests hold loops still; this one lets the ring run to see it move.
  testWidgets('writes the ring round while motion is on', (tester) async {
    AppMotion.loopsEnabled = true;
    addTearDown(() => AppMotion.loopsEnabled = false);
    await pump(tester, const InkRingIndicator());

    await tester.pump(const Duration(milliseconds: 200));
    final early = paintOf(tester, InkRingIndicator).painter!;
    await tester.pump(const Duration(milliseconds: 300));
    final later = paintOf(tester, InkRingIndicator).painter!;
    expect(later.shouldRepaint(early), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stands still with reduced motion', (tester) async {
    AppMotion.loopsEnabled = true;
    addTearDown(() => AppMotion.loopsEnabled = false);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: InkStampIndicator())),
      ),
    );
    // Settles: nothing repeats.
    await tester.pumpAndSettle();

    final stamp = paintOf(tester, InkStampIndicator).painter! as StampStrokes;
    expect((stamp.ring, stamp.stem, stamp.branch), (1, 1, 1));
  });
}
