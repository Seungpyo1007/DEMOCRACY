import 'package:democracy/src/design/app_tokens.dart';
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

  static const _node = 12.0;
  static const _connector = 2.0;

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: _node,
                      height: _node,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        // Square on iOS, round on Android -- the same
                        // inversion the guide applies to bar tracks.
                        shape: surface.isGlass
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                      ),
                    ),
                    if (i != steps.length - 1)
                      const Expanded(
                        child: SizedBox(
                          width: _connector,
                          child: ColoredBox(color: AppColors.neutral300),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == steps.length - 1 ? 0 : AppSpacing.x3 + 2,
                    ),
                    child: _Step(step: steps[i]),
                  ),
                ),
              ],
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
        Text(
          step.title,
          style: AppTextStyles.cardBody.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(
          '${step.detail} · ${step.stamp}',
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
        ),
        if (step.evidence != null) ...[
          const SizedBox(height: AppSpacing.x1),
          step.evidence!,
        ],
      ],
    );
  }
}
