import 'dart:convert';

import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The weights and inputs the match ran on, unformatted.
///
/// This page is what makes the pinned disclosure more than a disclaimer. A
/// claim that an algorithm is open is only checkable if the thing it ran on
/// can be read, so the payload is printed as it arrived rather than summarised
/// into prose that could quietly disagree with it.
class AlgorithmLogScreen extends ConsumerWidget {
  const AlgorithmLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(matchReportProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PlatformAdaptiveAppBar.of(context, title: '알고리즘 검증'),
      body: AsyncSection<MatchReport>(
        value: report,
        onRetry: () => ref.invalidate(matchReportProvider),
        builder: (context, data) => _Log(report: data),
      ),
    );
  }
}

class _Log extends StatelessWidget {
  const _Log({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screen),
      children: [
        Text('이 점수가 어떻게 나왔는지', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '아래는 이번 분석에 실제로 들어간 가중치와 입력값입니다. '
          '요약하지 않고 그대로 싣습니다.',
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral700),
        ),
        const SizedBox(height: AppSpacing.x6),

        const SectionLabel('대조한 공약'),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '${report.comparedPledges}건',
          style: AppTextStyles.statValue.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.x6),

        const SectionLabel('가중치와 입력값'),
        const SizedBox(height: AppSpacing.x2),
        AppCard(
          child: SelectableText(
            encoder.convert(report.weights),
            style: AppTextStyles.cardBody.copyWith(
              fontFamily: 'monospace',
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x6),

        const DisclaimerBox(
          text:
              '이 결과는 공약 원문 기반 참고 자료이며 공인 평가가 아닙니다. '
              '가중치에 이의가 있다면 그대로 반박할 수 있도록 원본을 공개합니다.',
        ),
      ],
    );
  }
}
