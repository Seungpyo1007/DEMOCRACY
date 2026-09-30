import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The weights and inputs the match ran on, as they arrived.
///
/// This page is what makes the pinned disclosure more than a disclaimer. A
/// claim that an algorithm is open is only checkable if the thing it ran on
/// can be read, so the payload is laid out key by key exactly as it arrived --
/// set as readable rows rather than a code block, but never summarised into
/// prose that could quietly disagree with it.
class AlgorithmLogScreen extends ConsumerWidget {
  const AlgorithmLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(matchReportProvider);

    // The chrome stands while the payload loads, so the way back is there
    // from the first frame rather than appearing with the data.
    return Scaffold(
      body: EditorialScrollView(
        kicker: '알고리즘 검증',
        title: '이 점수가 어떻게 나왔는지',
        onBack: context.canPop() ? () => context.pop() : null,
        bottomPadding: AppSpacing.x12,
        slivers: [
          SliverToBoxAdapter(
            child: AsyncSection<MatchReport>(
              value: report,
              onRetry: () => ref.invalidate(matchReportProvider),
              builder: (context, data) => _Log(report: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _Log extends StatelessWidget {
  const _Log({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    final generated = report.generatedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x3,
        AppSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RevealIn(
            child: Text(
              '아래는 이번 분석에 실제로 들어간 가중치와 입력값입니다. '
              '요약하지 않고 받은 그대로 싣습니다.',
              style: AppTextStyles.reading.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          RevealIn(
            index: 1,
            child: FigureRow(
              children: [
                FigureStat(
                  value: report.comparedPledges,
                  unit: '건',
                  label: '대조한 공약',
                ),
                if (generated != null)
                  _TextStat(
                    value: KstInstant.fromDateTime(generated).dayLabel,
                    label: '산출일',
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x8),
          RevealIn(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(number: '01', label: '가중치와 입력값'),
                const SizedBox(height: AppSpacing.x1),
                const SourceLine('키 이름과 값은 받은 그대로입니다.'),
                const SizedBox(height: AppSpacing.x2),
                ..._entries(report.weights, depth: 0),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x8),
          const RevealIn(
            index: 3,
            child: DisclaimerBox(
              text:
                  '이 결과는 공약 원문 기반 참고 자료이며 공인 평가가 아닙니다. '
                  '가중치에 이의가 있다면 그대로 반박할 수 있도록 원본을 공개합니다.',
            ),
          ),
        ],
      ),
    );
  }

  /// One ruled row per key. A nested object gets its key as a small heading
  /// and its own rows indented under it, so the shape of the payload is still
  /// visible without reading braces.
  List<Widget> _entries(Map<Object?, Object?> map, {required int depth}) {
    return [
      for (final entry in map.entries)
        if (entry.value is Map)
          Padding(
            padding: EdgeInsets.only(left: depth * AppSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RuledRow(minHeight: 44, child: _Key(entry.key.toString())),
                ..._entries(entry.value! as Map, depth: depth + 1),
              ],
            ),
          )
        else
          Padding(
            padding: EdgeInsets.only(left: depth * AppSpacing.x4),
            child: RuledRow(
              minHeight: 44,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _Key(entry.key.toString())),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    flex: 3,
                    child: SelectableText(
                      _value(entry.value),
                      textAlign: TextAlign.end,
                      style: AppTextStyles.cardBody.copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  static String _value(Object? value) => switch (value) {
    final List<Object?> list => list.join(', '),
    null => 'null',
    _ => value.toString(),
  };
}

class _Key extends StatelessWidget {
  const _Key(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      style: AppTextStyles.ctaSmall.copyWith(color: AppColors.neutral700),
    );
  }
}

/// A figure that is a word rather than a number, set like [FigureStat].
class _TextStat extends StatelessWidget {
  const _TextStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: AppTextStyles.statValue.copyWith(
              color: AppColors.ink,
              fontSize: 30,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          label,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }
}
