import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    TargetPlatform platform,
    Widget child,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration decorationOf(WidgetTester tester, Finder finder) {
    return tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;
  }

  group('AppCard', () {
    // The whole reason the card exists: one caller, two materials.
    testWidgets('blurs on iOS and does not on Android', (tester) async {
      await pump(tester, TargetPlatform.iOS, const AppCard(child: Text('x')));
      expect(find.byType(BackdropFilter), findsOneWidget);

      await pump(
        tester,
        TargetPlatform.android,
        const AppCard(child: Text('x')),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('is translucent on iOS and opaque on Android', (tester) async {
      await pump(tester, TargetPlatform.iOS, const AppCard(child: Text('x')));
      final glass = decorationOf(
        tester,
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      expect(glass.color!.a, lessThan(1.0));

      await pump(
        tester,
        TargetPlatform.android,
        const AppCard(child: Text('x')),
      );
      final opaque = decorationOf(
        tester,
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      expect(opaque.color!.a, 1.0);
    });
  });

  group('LabeledBar', () {
    // The fill first shipped at zero height: a ColoredBox has no child to take
    // a height from, so the track rendered empty while widthFactor was
    // perfectly correct. Measuring the painted box is what catches that.
    testWidgets('actually paints the fill across the track height', (
      tester,
    ) async {
      await pump(
        tester,
        TargetPlatform.android,
        const SizedBox(
          width: 200,
          child: LabeledBar(
            label: '교통',
            fraction: 0.5,
            valueText: '72%',
            trackHeight: 10,
          ),
        ),
      );

      final fill = tester.getSize(find.byType(FractionallySizedBox));
      expect(fill.height, 10);
      expect(fill.width, greaterThan(0));
    });

    testWidgets('clamps a fraction that leaves the range', (tester) async {
      await pump(
        tester,
        TargetPlatform.android,
        const LabeledBar(label: '소통', fraction: 4.1, valueText: '4.1'),
      );

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, 1.0);
    });

    testWidgets('draws a square track on iOS and a round one on Android', (
      tester,
    ) async {
      const bar = LabeledBar(label: '교통', fraction: 0.72, valueText: '72%');

      await pump(tester, TargetPlatform.iOS, bar);
      final ios = tester
          .widgetList<ClipRRect>(find.byType(ClipRRect))
          .last
          .borderRadius;
      expect(ios, BorderRadius.zero);

      await pump(tester, TargetPlatform.android, bar);
      final android = tester
          .widgetList<ClipRRect>(find.byType(ClipRRect))
          .last
          .borderRadius;
      expect(android, isNot(BorderRadius.zero));
    });
  });

  group('MonotonicBar', () {
    // A share that falls between polls is an out-of-order update, not news.
    testWidgets('holds its high-water mark when the value drops', (
      tester,
    ) async {
      Future<void> pumpAt(double fraction) => pump(
        tester,
        TargetPlatform.android,
        MonotonicBar(label: '박서연', fraction: fraction, valueText: '48.2%'),
      );

      await pumpAt(0.48);
      await pumpAt(0.30);
      await tester.pumpAndSettle();

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, closeTo(0.48, 0.001));
    });

    testWidgets('follows the value up', (tester) async {
      Future<void> pumpAt(double fraction) => pump(
        tester,
        TargetPlatform.android,
        MonotonicBar(label: '박서연', fraction: fraction, valueText: '52.0%'),
      );

      await pumpAt(0.48);
      await pumpAt(0.52);
      await tester.pumpAndSettle();

      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, closeTo(0.52, 0.001));
    });
  });

  group('AppFilterChip', () {
    // Selection carried by fill alone is a state some readers cannot see.
    testWidgets('Android marks selection with a tick as well as a fill', (
      tester,
    ) async {
      await pump(
        tester,
        TargetPlatform.android,
        AppFilterChip(label: '30대', selected: true, onSelected: (_) {}),
      );

      expect(find.text('✓ 30대'), findsOneWidget);
    });

    testWidgets('reports the toggle', (tester) async {
      final changes = <bool>[];
      await pump(
        tester,
        TargetPlatform.iOS,
        AppFilterChip(label: '세금', selected: false, onSelected: changes.add),
      );

      await tester.tap(find.text('세금'));
      await tester.pump();

      expect(changes, [true]);
    });
  });

  group('AppSwitch', () {
    testWidgets('reports the flip and exposes its state', (tester) async {
      final changes = <bool>[];
      await pump(
        tester,
        TargetPlatform.iOS,
        AppSwitch(
          value: false,
          onChanged: changes.add,
          semanticLabel: '실명으로 작성',
        ),
      );

      await tester.tap(find.byType(AppSwitch));
      await tester.pump();

      expect(changes, [true]);
    });
  });

  group('AppSegmentedControl', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('$platform reports the chosen segment', (tester) async {
        final picked = <int>[];
        await pump(
          tester,
          platform,
          AppSegmentedControl(
            segments: const ['실시간', '역대 결과', '여론조사 비교'],
            selectedIndex: 0,
            onSelected: picked.add,
          ),
        );

        await tester.tap(find.textContaining('역대 결과'));
        await tester.pump();

        expect(picked, [1]);
      });
    }
  });

  group('VerifiedBadge', () {
    // Green is a status here, and status is never colour alone.
    testWidgets('always carries a tick and a word', (tester) async {
      await pump(
        tester,
        TargetPlatform.android,
        const VerifiedBadge(label: '주민 인증됨'),
      );

      expect(find.text('✓ 주민 인증됨'), findsOneWidget);
    });

    testWidgets('keeps its shape when not verified', (tester) async {
      await pump(
        tester,
        TargetPlatform.android,
        const VerifiedBadge(label: '인증 대기', verified: false),
      );

      expect(find.text('✓ 인증 대기'), findsOneWidget);
    });
  });

  group('AppTimeline', () {
    testWidgets('shows every step rather than only the outcome', (
      tester,
    ) async {
      await pump(
        tester,
        TargetPlatform.iOS,
        const AppTimeline(
          steps: [
            TimelineStep(
              title: 'AI 1차 판단',
              detail: '착공 보도·예산 집행 데이터 감지',
              stamp: '3월 2일',
            ),
            TimelineStep(
              title: '시민 제보 12건',
              detail: '현장 사진·입주 공고 첨부',
              stamp: '4월',
            ),
            TimelineStep(
              title: '전문가 위원회 최종 판정: 이행 완료',
              detail: '위원 7인 합의',
              stamp: '5월 10일',
            ),
          ],
        ),
      );

      expect(find.text('AI 1차 판단'), findsOneWidget);
      expect(find.text('시민 제보 12건'), findsOneWidget);
      expect(find.text('전문가 위원회 최종 판정: 이행 완료'), findsOneWidget);
    });
  });

  group('AppPrimaryButton', () {
    testWidgets('a null callback disables it without hiding it', (
      tester,
    ) async {
      await pump(
        tester,
        TargetPlatform.android,
        const AppPrimaryButton(label: '평가 작성하기', onPressed: null),
      );

      expect(find.text('평가 작성하기'), findsOneWidget);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppPrimaryButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, isNot(AppColors.signal));
    });
  });
}
