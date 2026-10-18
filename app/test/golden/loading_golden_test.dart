@Tags(['golden'])
library;

import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden_harness.dart';

/// The loading marks, per platform: the ink stamp and written rows on iOS,
/// Material 3's indicators on Android.
///
/// No screen golden is taken mid-load, so without this a change to either
/// platform's loading would pass unseen. Loops are held still here, so each
/// mark is the frame a reader sees with reduced motion.
void main() {
  goldenPlatforms.forEach((name, platform) {
    testWidgets('loading marks on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const _LoadingMarks(),
        platform: platform,
        withDistrict: false,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/loading_${name}_390dp.png'),
      );
    });
  });
}

class _LoadingMarks extends StatelessWidget {
  const _LoadingMarks();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const SectionLabel('화면'),
          const SizedBox(height: AppSpacing.x3),
          const Center(child: InkStampIndicator(size: 56)),
          const SizedBox(height: AppSpacing.x6),
          const SectionLabel('줄 옆'),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              const InkStampIndicator(),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  '후보별 공약 원문을 대조하고 있습니다',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          const SectionLabel('섹션'),
          const SizedBox(height: AppSpacing.x3),
          const InkLoadingRows(rows: 4),
          const SizedBox(height: AppSpacing.x6),
          // Pull to refresh's puck; on iOS the stamp, with nothing behind.
          const SectionLabel('당겨서 새로고침'),
          const SizedBox(height: AppSpacing.x3),
          const Center(
            child: InkStampIndicator(size: 48, delayed: false, contained: true),
          ),
        ],
      ),
    );
  }
}
