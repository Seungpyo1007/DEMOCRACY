import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/material.dart';

/// One step in a decision's history.
///
/// [evidence] is separate from [detail] because a reversal is not allowed to
/// stand on a summary: the guide requires a link to the source it was reversed
/// against, and keeping it its own field means a caller cannot satisfy the rule
/// by writing the URL into prose.
class TimelineStep {
  const TimelineStep({
    required this.title,
    required this.detail,
    required this.stamp,
    this.evidence,
  });

  final String title;
  final String detail;
  final String stamp;
  final Widget? evidence;
}

/// The judgement pipeline: who decided what, in order, and when.
///
/// The whole point of the screen it sits on is to answer "who judged this and
/// how", so the steps are always shown in full rather than collapsed behind a
/// summary of the outcome.
class AppTimeline extends StatelessWidget {
  const AppTimeline({required this.steps, super.key});

  static const _node = 28.0;

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          RevealIn(
            index: i,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      // Numbered, because the order is the point: AI first,
                      // then residents, then the committee.
                      Container(
                        width: _node,
                        height: _node,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: AppTextStyles.figureSmall.copyWith(
                            fontSize: 14,
                            color: AppColors.ground,
                          ),
                        ),
                      ),
                      if (i != steps.length - 1)
                        const Expanded(
                          child: SizedBox(
                            width: 1,
                            child: ColoredBox(color: AppColors.neutral300),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 3,
                        bottom: i == steps.length - 1 ? 0 : AppSpacing.x6,
                      ),
                      child: _Step(step: steps[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.step});

  final TimelineStep step;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                step.title,
                style: AppTextStyles.cardBody.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Text(
              step.stamp,
              style: AppTextStyles.disclaimer.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          step.detail,
          style: AppTextStyles.cardBody.copyWith(
            fontSize: 14,
            color: AppColors.neutral700,
          ),
        ),
        if (step.evidence != null) ...[
          const SizedBox(height: AppSpacing.x1),
          step.evidence!,
        ],
      ],
    );
  }
}
