@Tags(['golden'])
library;

import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden_harness.dart';

/// Every shared component on one page, per platform.
///
/// The screen goldens each cover a handful of these in one arrangement; this
/// covers all of them in isolation, so a change to a component shows up here
/// as itself rather than as six screens moving at once.
void main() {
  goldenPlatforms.forEach((name, platform) {
    testWidgets('component catalogue on $name', (tester) async {
      await pumpGolden(
        tester,
        screen: const _Catalogue(),
        platform: platform,
        withDistrict: false,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/catalogue_${name}_390dp.png'),
      );
    });
  });
}

class _Catalogue extends StatelessWidget {
  const _Catalogue();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const SectionLabel('상태 칩'),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (final status in PledgeStatus.values)
                PledgeStatusChip(status: status),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('뱃지와 스탯'),
          const SizedBox(height: AppSpacing.x2),
          const Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              VerifiedBadge(label: '주민 인증됨'),
              VerifiedBadge(label: '인증 대기', verified: false),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          const Row(
            children: [
              Expanded(
                child: StatCell(value: '92%', label: '출석률'),
              ),
              Expanded(
                child: StatCell(value: '31', label: '발의 법안'),
              ),
              Expanded(
                child: StatCell(value: '58%', label: '공약 이행'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('바'),
          const SizedBox(height: AppSpacing.x2),
          const LabeledBar(
            label: '교통',
            fraction: 0.72,
            valueText: '72%',
            fillColor: AppColors.fulfilled,
          ),
          const SizedBox(height: AppSpacing.x2),
          const LabeledBar(
            label: '주거',
            fraction: 0.55,
            valueText: '55%',
            fillColor: AppColors.inProgress,
          ),
          const SizedBox(height: AppSpacing.x2),
          const MonotonicBar(label: '박서연', fraction: 0.482, valueText: '48.2%'),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('카드'),
          const SizedBox(height: AppSpacing.x2),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MicroLabel('감지된 지역구'),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '서울 마포구 을',
                      style: AppTextStyles.statValue.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const VerifiedBadge(label: '인증 가능'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('컨트롤'),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              AppFilterChip(label: '30대', selected: true, onSelected: (_) {}),
              AppFilterChip(label: '자영업', selected: false, onSelected: (_) {}),
              AppFilterChip(label: '1인 가구', selected: true, onSelected: (_) {}),
              AppFilterChip(label: '부동산', selected: false, onSelected: (_) {}),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              AppSwitch(
                value: false,
                onChanged: (_) {},
                semanticLabel: '실명으로 작성',
              ),
              const SizedBox(width: AppSpacing.x3),
              AppSwitch(
                value: true,
                onChanged: (_) {},
                semanticLabel: '실명으로 작성',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          AppSegmentedControl(
            segments: const ['실시간', '역대 결과'],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('타임라인'),
          const SizedBox(height: AppSpacing.x2),
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
            ],
          ),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('고지'),
          const SizedBox(height: AppSpacing.x2),
          const DisclaimerBox(
            text: '공약 원문 기반 참고 자료 · 공인 평가 아님',
            tone: DisclaimerTone.pinned,
          ),
          const SizedBox(height: AppSpacing.x2),
          const DisclaimerBox(text: '주소 인증 주민만 작성 가능 · 조작 방지 알고리즘 적용'),
          const SizedBox(height: AppSpacing.x6),

          const SectionLabel('액션'),
          const SizedBox(height: AppSpacing.x2),
          AppPrimaryButton(
            label: '지역구 설정 완료',
            trailingArrow: true,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.x2),
          const AppPrimaryButton(label: '평가 작성하기', onPressed: null),
          const SizedBox(height: AppSpacing.x3),
          Align(
            alignment: Alignment.centerRight,
            child: AppExtendedFab(
              label: '이행 제보',
              icon: Icons.add,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
