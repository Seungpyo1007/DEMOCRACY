import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/expressive_loading_indicator.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The ink is the iOS page; Android draws Material's indicators (below).
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    TargetPlatform platform = TargetPlatform.iOS,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform),
        home: Scaffold(
          body: Center(child: SizedBox(width: 300, child: child)),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester, Type type) {
    return tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(type),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
  }

  double strokeWidth(WidgetTester tester, int row) {
    return tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .elementAt(row)
        .widthFactor!;
  }

  StampStrokes stampOf(WidgetTester tester) {
    return tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(InkStampIndicator),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as StampStrokes;
  }

  testWidgets('shows nothing for a load shorter than the delay', (
    tester,
  ) async {
    await pump(tester, const InkLoadingRows());

    await tester.pump(appearDelay - const Duration(milliseconds: 10));
    expect(opacityOf(tester, InkLoadingRows), 0);

    await tester.pumpAndSettle();
    expect(opacityOf(tester, InkLoadingRows), 1);
  });

  testWidgets('rules the rows the content will land on', (tester) async {
    await pump(tester, const InkLoadingRows(rows: 4));
    await tester.pumpAndSettle();

    expect(find.byType(FractionallySizedBox), findsNWidgets(4));
    expect(tester.getSize(find.byType(InkLoadingRows)).height, 4 * 54);
    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
  });

  // Tests hold loops still; this one lets them run to see them move.
  testWidgets('writes the strokes row after row while motion is on', (
    tester,
  ) async {
    AppMotion.loopsEnabled = true;
    addTearDown(() => AppMotion.loopsEnabled = false);
    await pump(tester, const InkLoadingRows());

    await tester.pump(const Duration(milliseconds: 300));
    final early = strokeWidth(tester, 0);
    await tester.pump(const Duration(milliseconds: 300));
    final later = strokeWidth(tester, 0);
    expect(later, greaterThan(early));
    // The second row (0.78 long to the first's 0.62) is behind the first.
    expect(strokeWidth(tester, 1) / 0.78, lessThan(later / 0.62));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('draws the stamp stroke by stroke while motion is on', (
    tester,
  ) async {
    AppMotion.loopsEnabled = true;
    addTearDown(() => AppMotion.loopsEnabled = false);
    await pump(tester, const InkStampIndicator());

    await tester.pump(const Duration(milliseconds: 400));
    final early = stampOf(tester);
    expect(early.ring, inExclusiveRange(0, 1));
    expect(early.stem, 0);
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(stampOf(tester).branch, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stands still with reduced motion', (tester) async {
    AppMotion.loopsEnabled = true;
    addTearDown(() => AppMotion.loopsEnabled = false);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light(TargetPlatform.iOS),
          home: const Scaffold(body: InkStampIndicator()),
        ),
      ),
    );
    // Settles: nothing repeats.
    await tester.pumpAndSettle();

    final stamp = stampOf(tester);
    expect((stamp.ring, stamp.stem, stamp.branch), (1, 1, 1));
  });

  testWidgets('pull to refresh shows the stamp alone and runs the refresh', (
    tester,
  ) async {
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TargetPlatform.iOS),
        home: Scaffold(
          body: InkRefresh(
            onRefresh: () async => refreshed++,
            child: ListView(
              children: [for (var i = 0; i < 30; i++) Text('줄 $i')],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(InkStampIndicator), findsNothing);
    await tester.fling(find.text('줄 0'), const Offset(0, 400), 1000);
    await tester.pump();
    expect(find.byType(InkStampIndicator), findsOneWidget);
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    // Nothing drawn behind it: one mark, not a disc and a mark.
    expect(
      find.ancestor(
        of: find.byType(InkStampIndicator),
        matching: find.descendant(
          of: find.byType(InkRefresh),
          matching: find.byType(DecoratedBox),
        ),
      ),
      findsNothing,
    );

    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(find.byType(InkStampIndicator), findsNothing);
  });

  group('on Android', () {
    const android = TargetPlatform.android;

    Finder stampPaint() => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is StampStrokes,
    );

    testWidgets("shows M3 Expressive's loading indicator, not the stamp", (
      tester,
    ) async {
      await pump(
        tester,
        const Center(child: InkStampIndicator(size: 56)),
        platform: android,
      );
      await tester.pumpAndSettle();

      expect(stampPaint(), findsNothing);
      final indicator = tester.widget<ExpressiveLoadingIndicator>(
        find.byType(ExpressiveLoadingIndicator),
      );
      expect(indicator.contained, isFalse);
      // A screen-sized wait takes the spec's 48dp box.
      expect(
        tester.getSize(find.byType(ExpressiveLoadingIndicator)),
        const Size.square(48),
      );
      expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
    });

    testWidgets('an inline mark is fitted to its spot and keeps its colour', (
      tester,
    ) async {
      await pump(
        tester,
        const Center(child: InkStampIndicator(size: 20, color: Colors.white)),
        platform: android,
      );
      await tester.pumpAndSettle();

      final indicator = tester.widget<ExpressiveLoadingIndicator>(
        find.byType(ExpressiveLoadingIndicator),
      );
      expect(indicator.color, Colors.white);
      expect(
        tester.getSize(find.byType(ExpressiveLoadingIndicator)),
        const Size.square(20),
      );
    });

    testWidgets('still waits out the delay before it appears', (tester) async {
      await pump(tester, const InkStampIndicator(), platform: android);

      await tester.pump(appearDelay - const Duration(milliseconds: 10));
      expect(opacityOf(tester, InkStampIndicator), 0);
      await tester.pumpAndSettle();
      expect(opacityOf(tester, InkStampIndicator), 1);
    });

    testWidgets('turns and morphs while motion is on', (tester) async {
      AppMotion.loopsEnabled = true;
      addTearDown(() => AppMotion.loopsEnabled = false);
      await pump(tester, const InkStampIndicator(), platform: android);

      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(ExpressiveLoadingIndicator),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;

      await tester.pump(const Duration(milliseconds: 300));
      final early = painter();
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter().shouldRepaint(early), isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('holds one still shape with reduced motion', (tester) async {
      AppMotion.loopsEnabled = true;
      addTearDown(() => AppMotion.loopsEnabled = false);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.light(android),
            home: const Scaffold(body: InkStampIndicator()),
          ),
        ),
      );
      // Settles: nothing repeats.
      await tester.pumpAndSettle();
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });

    testWidgets('section rows keep their height, still, beside the indicator', (
      tester,
    ) async {
      AppMotion.loopsEnabled = true;
      addTearDown(() => AppMotion.loopsEnabled = false);
      await pump(tester, const InkLoadingRows(rows: 4), platform: android);

      await tester.pump(const Duration(milliseconds: 300));
      final early = strokeWidth(tester, 0);
      await tester.pump(const Duration(milliseconds: 300));
      // The rows do not write themselves in; only the indicator moves.
      expect(strokeWidth(tester, 0), early);

      expect(tester.getSize(find.byType(InkLoadingRows)).height, 4 * 54);
      expect(find.byType(FractionallySizedBox), findsNWidgets(4));
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // In the first row's free end.
      final rows = tester.getRect(find.byType(InkLoadingRows));
      final indicator = tester.getRect(find.byType(ExpressiveLoadingIndicator));
      expect(indicator.right, rows.right);
      expect(indicator.center.dy, rows.top + 27);
      expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pull to refresh puts the contained indicator in a puck', (
      tester,
    ) async {
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(android),
          home: Scaffold(
            body: InkRefresh(
              onRefresh: () async => refreshed++,
              child: ListView(
                children: [for (var i = 0; i < 30; i++) Text('줄 $i')],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
      await tester.fling(find.text('줄 0'), const Offset(0, 400), 1000);
      await tester.pump();

      final indicator = tester.widget<ExpressiveLoadingIndicator>(
        find.byType(ExpressiveLoadingIndicator),
      );
      expect(indicator.contained, isTrue);
      expect(stampPaint(), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();
      expect(refreshed, 1);
      expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    });
  });
}
