import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/material.dart';

/// What stands where a figure the law forbids publishing would have been.
///
/// It names the provision. A panel that simply goes blank reads as a bug, and
/// a reader who cannot tell a legal restriction from a broken screen learns
/// the wrong thing about both -- so the restriction is stated, along with when
/// it lifts. That is the same reasoning as `AsyncSection` reporting a missing
/// source as a missing source rather than as a generic failure.
///
/// Set as a notice in the record rather than as an empty state: the article
/// in pine, a serif headline, the rule in the law's own words, and the moment
/// it lifts, between two 2px rules.
///
/// There is deliberately no countdown. A remaining time that does not tick is
/// wrong a minute after it is drawn, and one that does tick is a timer on a
/// screen whose deadline the provider already re-evaluates -- the opening
/// time is the fact, and it stays true.
class EmbargoNotice extends StatelessWidget {
  const EmbargoNotice({
    required this.article,
    required this.notice,
    this.headline = '지금은 표시할 수 없습니다',
    this.until,
    super.key,
  });

  /// The provision being complied with, e.g. '공직선거법 제108조제1항'.
  final String article;

  final String notice;

  /// What is withheld, said plainly: '지금은 여론조사 결과를 표시할 수 없습니다'.
  final String headline;

  /// When the restriction lifts. Drawn as a figure when given; the [notice]
  /// states it either way.
  final KstInstant? until;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screen,
        vertical: AppSpacing.x6,
      ),
      child: Semantics(
        container: true,
        label: '공개 제한 안내',
        child: RevealIn(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: AppColors.ink, width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.x6 - 2,
                0,
                AppSpacing.x6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    article,
                    // Pine, and only here: the article is the one thing on
                    // this notice a reader may want to look up.
                    style: AppTextStyles.sectionLabel.copyWith(
                      color: AppColors.signal,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3 + 2),
                  Semantics(
                    header: true,
                    child: Text(
                      headline,
                      style: theme.headlineSmall?.copyWith(
                        color: AppColors.ink,
                        fontSize: 28,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3 + 2),
                  Text(
                    notice,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.neutral700,
                      height: 1.6,
                    ),
                  ),
                  if (until != null) ...[
                    const SizedBox(height: AppSpacing.x4),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.x3 + 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '공개 시각',
                              style: AppTextStyles.statLabel.copyWith(
                                color: AppColors.neutral600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              until!.stampLabel,
                              style: AppTextStyles.figureSmall.copyWith(
                                color: AppColors.ink,
                                fontSize: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
