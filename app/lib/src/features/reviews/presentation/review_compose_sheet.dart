import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a review is written.
///
/// Four axes rather than one overall star: a resident who rates communication
/// well and delivery badly should be able to say that instead of averaging it
/// themselves into a number that says neither.
class ReviewComposeSheet extends ConsumerStatefulWidget {
  const ReviewComposeSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return PlatformAdaptiveSheet.show<bool>(
      context: context,
      builder: (context) => const ReviewComposeSheet(),
    );
  }

  @override
  ConsumerState<ReviewComposeSheet> createState() => _ReviewComposeSheetState();
}

class _ReviewComposeSheetState extends ConsumerState<ReviewComposeSheet> {
  ReviewDraft _draft = const ReviewDraft();
  ContentWarning? _warning;

  /// Set once the author has been warned and chose to continue. The guide asks
  /// for interception before sending, not for a block -- the resident, not the
  /// app, decides whether their sentence stands.
  bool _acknowledged = false;

  Future<void> _submit() async {
    final warning = ContentGuard.inspect(_draft.body);
    if (warning != null && !_acknowledged) {
      setState(() {
        _warning = warning;
        _acknowledged = true;
      });
      return;
    }

    final posted = await ref
        .read(reviewSubmissionProvider.notifier)
        .submit(_draft);

    if (posted && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = ref.watch(reviewSubmissionProvider).isLoading;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.x4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.x4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('주민 평가 작성'),
            const SizedBox(height: AppSpacing.x3),

            for (final axis in ReviewDraft.axes) ...[
              _AxisRating(
                label: axis,
                score: _draft.scores[axis] ?? 0,
                onChanged: (score) =>
                    setState(() => _draft = _draft.withScore(axis, score)),
              ),
              const SizedBox(height: AppSpacing.x2),
            ],

            const SizedBox(height: AppSpacing.x3),
            TextField(
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              onChanged: (value) => setState(() {
                _draft = _draft.withBody(value);
                // A changed sentence has not been warned about yet.
                _acknowledged = false;
                _warning = null;
              }),
              decoration: const InputDecoration(
                hintText: '무엇을 보고 그렇게 판단하셨는지 적어 주세요.',
              ),
            ),

            if (_warning != null) ...[
              const SizedBox(height: AppSpacing.x2),
              DisclaimerBox(text: '${_warning!.message} 그대로 올리려면 한 번 더 누르세요.'),
              const SizedBox(height: AppSpacing.x2),
            ],

            Row(
              children: [
                AppSwitch(
                  value: !_draft.anonymous,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.withAnonymous(!value)),
                  semanticLabel: '실명으로 작성',
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    _draft.anonymous
                        ? '익명으로 작성 · 게시 후 변경할 수 없습니다'
                        : '실명으로 작성 · 게시 후 변경할 수 없습니다',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.x4),
            if (_draft.blockedReason != null) ...[
              Text(
                _draft.blockedReason!,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
            ],
            AppPrimaryButton(
              label: submitting ? '올리는 중' : '평가 올리기',
              onPressed: _draft.isComplete && !submitting ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One axis, rated by tapping or dragging across the stars.
class _AxisRating extends StatelessWidget {
  const _AxisRating({
    required this.label,
    required this.score,
    required this.onChanged,
  });

  static const _star = 30.0;

  final String label;
  final int score;
  final ValueChanged<int> onChanged;

  void _fromPosition(double dx) {
    final index = (dx / _star).floor() + 1;
    onChanged(index.clamp(ReviewDraft.minScore, ReviewDraft.maxScore));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
          ),
        ),
        Semantics(
          slider: true,
          label: label,
          value: '$score점',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _fromPosition(details.localPosition.dx),
            // Dragging as well as tapping, because five discrete targets
            // 30dp wide are easy to miss and a slip changes the rating.
            onHorizontalDragUpdate: (details) =>
                _fromPosition(details.localPosition.dx),
            child: SizedBox(
              height: 34,
              width: _star * ReviewDraft.maxScore,
              child: Row(
                children: [
                  for (var i = 1; i <= ReviewDraft.maxScore; i++)
                    SizedBox(
                      width: _star,
                      child: Icon(
                        i <= score ? Icons.star : Icons.star_border,
                        size: 22,
                        color: i <= score
                            ? AppColors.ink
                            : AppColors.neutral400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        Text(
          score == 0 ? '—' : '$score',
          style: AppTextStyles.badge.copyWith(color: AppColors.neutral700),
        ),
      ],
    );
  }
}
