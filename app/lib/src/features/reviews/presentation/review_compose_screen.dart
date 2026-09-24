import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_kicker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where a review is written: a page of its own, above the tab bar.
///
/// Four axes rather than one overall star: a resident who rates communication
/// well and delivery badly should be able to say that instead of averaging it
/// themselves into a number that says neither.
///
/// A page rather than a sheet because a review is a considered piece of
/// writing, and the anonymous choice -- the one thing here that cannot be
/// taken back -- belongs beside the words it will be attached to, not on the
/// hub where it would be set before anything was written.
///
/// Only verified residents arrive here: the hub's write action is behind
/// `VerifiedGate`. The page pops with `true` once the review is posted, and
/// the hub says so.
class ReviewComposeScreen extends ConsumerStatefulWidget {
  const ReviewComposeScreen({super.key});

  /// The key of the [score]th star on [axis]'s row.
  static Key starKey(String axis, int score) =>
      ValueKey('review-star-$axis-$score');

  /// Room the pinned submit button takes over the end of the page, so the
  /// last row can always be scrolled clear of it.
  static const _submitClearance = 52.0 + AppSpacing.x4 * 2;

  @override
  ConsumerState<ReviewComposeScreen> createState() =>
      _ReviewComposeScreenState();
}

class _ReviewComposeScreenState extends ConsumerState<ReviewComposeScreen> {
  /// Anonymous is the rest state: it is the choice the app cannot undo on
  /// the author's behalf, so it is the one they opt out of, not into.
  ReviewDraft _draft = ReviewDraft(anonymous: true);
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
      context.pop(true);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      // Opened from a link with nothing beneath it: the hub is where a
      // review is read, so that is where leaving it goes.
      context.go(AppRoutes.community);
    }
  }

  void _setAnonymous(bool value) {
    PlatformAdaptiveHaptics.selection();
    setState(() => _draft = _draft.withAnonymous(value));
  }

  void _setBody(String value) {
    setState(() {
      _draft = _draft.withBody(value);
      // A changed sentence has not been warned about yet.
      _acknowledged = false;
      _warning = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final submitting = ref.watch(reviewSubmissionProvider).isLoading;
    final blocked = _draft.blockedReason;
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.standard;

    final submit = AppPrimaryButton(
      label: submitting ? '올리는 중' : '평가 올리기',
      icon: AppIcons.write,
      onPressed: _draft.isComplete && !submitting ? _submit : null,
    );

    final page = EditorialScrollView(
      title: '주민 평가 작성',
      kicker: communityKicker(ref),
      onBack: _back,
      // iOS floats the button over the end of the page; Android sets it in
      // its own bar below, so only iOS needs the room reserved.
      bottomPadding: surface.isGlass
          ? ReviewComposeScreen._submitClearance
          : AppSpacing.x6,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.x4,
            AppSpacing.screen,
            0,
          ),
          sliver: SliverList.list(
            children: [
              RevealIn(
                child: SectionHeader(number: '01', label: '항목별 별점'),
              ),
              for (var i = 0; i < ReviewDraft.axes.length; i++)
                RevealIn(
                  index: i + 1,
                  child: _AxisRating(
                    label: ReviewDraft.axes[i],
                    score: _draft.scores[ReviewDraft.axes[i]] ?? 0,
                    onChanged: (score) {
                      final axis = ReviewDraft.axes[i];
                      if (score != _draft.scores[axis]) {
                        PlatformAdaptiveHaptics.selection();
                      }
                      setState(() => _draft = _draft.withScore(axis, score));
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.x6),
              const RevealIn(
                index: 5,
                child: SectionHeader(number: '02', label: '내용'),
              ),
              const SizedBox(height: AppSpacing.x3),
              RevealIn(index: 6, child: _BodyField(onChanged: _setBody)),
              AnimatedSize(
                duration: duration,
                curve: AppMotion.standardCurve,
                alignment: Alignment.topCenter,
                child: _warning == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.x2),
                        child: Semantics(
                          liveRegion: true,
                          child: DisclaimerBox(
                            text: '${_warning!.message} 그대로 올리려면 한 번 더 누르세요.',
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.x6),
              const RevealIn(
                index: 7,
                child: SectionHeader(number: '03', label: '공개 방식'),
              ),
              RevealIn(
                index: 8,
                child: _AnonymousRow(
                  value: _draft.anonymous,
                  onChanged: _setAnonymous,
                ),
              ),

              // What is still missing, in the margin hand. Announced as a
              // live region, so a screen reader hears it change as the author
              // fills the form in, not only a disabled button.
              AnimatedSwitcher(
                duration: duration,
                child: blocked == null
                    ? const SizedBox(
                        key: ValueKey('ready'),
                        height: AppSpacing.x2,
                      )
                    : Padding(
                        key: ValueKey(blocked),
                        padding: const EdgeInsets.only(top: AppSpacing.x4),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            liveRegion: true,
                            child: MarginNote(
                              blocked,
                              underline: false,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );

    // The page resizes for the keyboard, so on both platforms the submit
    // action rides just above it (or the home indicator) while writing.
    if (surface.isGlass) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: page),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: AppSpacing.x2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    0,
                    AppSpacing.x4,
                    AppSpacing.x2,
                  ),
                  child: submit,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Material 3: a bottom action bar holding the one filled button, on the
    // page's surface and set off by a hairline rather than floating.
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: page),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.ground,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4,
                  AppSpacing.x3,
                  AppSpacing.x4,
                  AppSpacing.x3,
                ),
                child: submit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The review text: Material 3's outlined field on Android, a grouped
/// Cupertino field on iOS.
class _BodyField extends StatelessWidget {
  const _BodyField({required this.onChanged});

  final ValueChanged<String> onChanged;

  static const _hint = '무엇을 보고 그렇게 판단하셨는지 적어 주세요.';
  static const _maxLength = 500;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    if (surface.isGlass) {
      return CupertinoTextField(
        minLines: 5,
        maxLines: 8,
        maxLength: _maxLength,
        onChanged: onChanged,
        placeholder: _hint,
        placeholderStyle: AppTextStyles.cardBody.copyWith(
          color: AppColors.neutral600,
        ),
        style: AppTextStyles.cardBody.copyWith(
          color: AppColors.ink,
          height: 1.5,
        ),
        padding: const EdgeInsets.all(AppSpacing.x3 + 2),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return TextField(
      minLines: 5,
      maxLines: 8,
      maxLength: _maxLength,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: '내용',
        hintText: _hint,
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// `익명으로 작성` with its consequence underneath, the whole row a target.
class _AnonymousRow extends StatelessWidget {
  const _AnonymousRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '익명으로 작성',
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '게시 후 변경할 수 없습니다',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            AppSwitch(
              value: value,
              onChanged: onChanged,
              semanticLabel: '익명으로 작성',
            ),
          ],
        ),
      ),
    );
  }
}

/// One axis, rated by tapping a star or dragging across them.
///
/// Each star is its own 44dp target and its own button for a screen reader,
/// `소통 4점`, so a rating can be set without having to aim or swipe.
class _AxisRating extends StatelessWidget {
  const _AxisRating({
    required this.label,
    required this.score,
    required this.onChanged,
  });

  static const _star = 44.0;

  final String label;
  final int score;
  final ValueChanged<int> onChanged;

  void _fromPosition(double dx) {
    final index = (dx / _star).floor() + 1;
    onChanged(index.clamp(ReviewDraft.minScore, ReviewDraft.maxScore));
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.quick;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _fromPosition(details.localPosition.dx),
              // Dragging as well as tapping, so a slip along the row settles
              // on the star the finger ends on rather than the one it started.
              onHorizontalDragUpdate: (details) =>
                  _fromPosition(details.localPosition.dx),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 1; i <= ReviewDraft.maxScore; i++)
                    Semantics(
                      key: ReviewComposeScreen.starKey(label, i),
                      button: true,
                      selected: i <= score,
                      label: '$label $i점',
                      onTap: () => onChanged(i),
                      excludeSemantics: true,
                      child: SizedBox(
                        width: _star,
                        height: _star,
                        child: Center(
                          child: AnimatedScale(
                            duration: duration,
                            curve: AppMotion.standardCurve,
                            scale: i == score ? 1.12 : 1,
                            child: Icon(
                              i <= score
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 28,
                              color: i <= score
                                  ? AppColors.ink
                                  : AppColors.neutral500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
