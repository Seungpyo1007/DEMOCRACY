import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final high = first > second ? first : second;
  final low = first > second ? second : first;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  group('the accent as text', () {
    // The design system says the accent-to-ground pair is tuned to 3:1 --
    // enough for icons and chrome, not for body copy -- and that
    // paragraph-size text in the accent must use accent-700 instead. These
    // numbers are why that instruction exists.
    test('is too light for body copy, and accent700 is not', () {
      for (final ground in [AppColors.white, AppColors.neutral100]) {
        expect(
          _contrast(AppColors.signal, ground),
          lessThan(4.5),
          reason: 'Signal on a page is large-text contrast at best',
        );
        expect(
          _contrast(AppColors.accent700, ground),
          greaterThanOrEqualTo(4.5),
          reason: 'accent700 is the ramp step that carries text',
        );
      }
    });

    test('still clears the 3:1 that chrome and icons need', () {
      expect(
        _contrast(AppColors.signal, AppColors.white),
        greaterThanOrEqualTo(3.0),
      );
    });

    // The one place a status reuses the brand colour. It is a chip label on a
    // pale tint, so it has to clear the body threshold rather than the chrome
    // one -- which is why the chip pair is accent-700 on accent-100.
    test('the 번복 chip reads as text, not as chrome', () {
      expect(
        _contrast(
          AppColors.reversedChipForeground,
          AppColors.reversedChipBackground,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('fixed-height boxes at a larger text size', () {
    // The guide assumes headroom for translation and for Dynamic Type. These
    // are the places a height is hardcoded around text, so they are the places
    // a reader who has turned text size up finds clipped. Testing the boxes
    // rather than whole screens keeps this fast and says which box broke.
    Future<List<String>> overflowsWhile(
      WidgetTester tester,
      Widget child, {
      required TargetPlatform platform,
      required double textScale,
      Size surface = const Size(390, 844),
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Capture overflows and forward everything else. Swallowing every
      // error turns a genuine crash into a silent retry loop, which is how
      // this helper first presented -- as a hang rather than a failure.
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exception.toString();
        if (message.contains('overflowed')) {
          errors.add(message);
          return;
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform),
          builder: (context, inner) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: inner!,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      );
      await tester.pump();

      return errors;
    }

    const tabItems = [
      AdaptiveTabItem(label: '지역구', icon: Icons.location_on_outlined),
      AdaptiveTabItem(label: '트래커', icon: Icons.donut_large_outlined),
      AdaptiveTabItem(label: 'AI 분석', icon: Icons.auto_awesome_outlined),
      AdaptiveTabItem(label: '커뮤니티', icon: Icons.forum_outlined),
      AdaptiveTabItem(label: '개표', icon: Icons.map_outlined),
    ];

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('$platform tab bar survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          PlatformAdaptiveTabBar(
            currentIndex: 0,
            items: tabItems,
            onTap: (_) {},
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });

      testWidgets('$platform disclaimer survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          const SizedBox(
            width: 350,
            child: DisclaimerBox(
              text: '공약 원문 기반 참고 자료이며 공인 평가가 아닙니다.',
              tone: DisclaimerTone.pinned,
            ),
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });

      testWidgets('$platform labelled bar survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          const SizedBox(
            width: 350,
            child: LabeledBar(label: '공약이행', fraction: 0.72, valueText: '72%'),
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });

      testWidgets('$platform stat row survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          const SizedBox(
            width: 350,
            child: Row(
              children: [
                Expanded(
                  child: StatCell(value: '92%', label: '출석률'),
                ),
                Expanded(
                  child: StatCell(value: '31건', label: '발의 법안'),
                ),
                Expanded(
                  child: StatCell(value: '58%', label: '공약 이행'),
                ),
              ],
            ),
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });

      testWidgets('$platform timeline survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          const SizedBox(
            width: 350,
            child: AppTimeline(
              steps: [
                TimelineStep(
                  title: '전문가 위원회 최종 판정',
                  detail: '위원 7인 중 6인 합의',
                  stamp: '5월 10일',
                ),
                TimelineStep(
                  title: 'AI 1차 판단',
                  detail: '착공 보도·예산 집행 데이터 감지',
                  stamp: '3월 2일',
                ),
              ],
            ),
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });

      testWidgets('$platform primary button survives 2x', (tester) async {
        final overflows = await overflowsWhile(
          tester,
          SizedBox(
            width: 350,
            child: AppPrimaryButton(
              label: '지역구 설정 완료',
              trailingArrow: true,
              onPressed: () {},
            ),
          ),
          platform: platform,
          textScale: 2.0,
        );

        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });
}
