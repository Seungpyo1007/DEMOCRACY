import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Reading is open to everyone; writing is not.
class ResidentReviewScreen extends ConsumerWidget {
  const ResidentReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const PlatformAdaptiveAppBar(title: '주민 평가'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          AsyncSection(
            value: ref.watch(reviewBoardProvider),
            onRetry: () => ref.invalidate(reviewBoardProvider),
            builder: (context, board) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryCard(summary: board.summary),
                const SizedBox(height: AppSpacing.x6),
                if (board.reviews.isEmpty)
                  Text(
                    '등록된 평가가 없습니다.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.neutral600,
                    ),
                  )
                else
                  for (final review in board.reviews) ...[
                    _ReviewCard(review: review),
                    const SizedBox(height: AppSpacing.x3),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          const _WriteNotice(),
          const SizedBox(height: AppSpacing.x4),
          VerifiedGate(
            onVerificationRequested: () => context.go(AppRoutes.onboarding),
            onVerified: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('작성 화면은 다음 단계에서 연결합니다.')),
              );
            },
            builder: (context, onPressed) {
              return FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('평가 작성하기'),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final surfaceTokens = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: AppColors.neutral200),
        borderRadius: BorderRadius.circular(surfaceTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  summary.averageDisplay,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(width: AppSpacing.x2),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.x1),
                  child: Text(
                    summary.respondentsDisplay,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            for (final axis in summary.axes) ...[
              _AxisRow(axis: axis),
              const SizedBox(height: AppSpacing.x2),
            ],
          ],
        ),
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.axis});

  final ReviewAxis axis;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            axis.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.x1),
            // Resident sentiment is not an official measurement, so it is
            // deliberately drawn in ink rather than in any status colour.
            child: LinearProgressIndicator(
              value: axis.score / 5,
              minHeight: 6,
              backgroundColor: AppColors.neutral200,
              valueColor: const AlwaysStoppedAnimation(AppColors.ink),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Text(axis.display, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final ResidentReview review;

  @override
  Widget build(BuildContext context) {
    final surfaceTokens = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: AppColors.neutral200),
        borderRadius: BorderRadius.circular(surfaceTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  review.author,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (review.verifiedResident) ...[
                  const SizedBox(width: AppSpacing.x2),
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: AppColors.fulfilled,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '인증 주민',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.fulfilled),
                  ),
                ],
                const Spacer(),
                Text(
                  '${review.score.toStringAsFixed(0)} / 5',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(review.body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _WriteNotice extends StatelessWidget {
  const _WriteNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral400),
        borderRadius: BorderRadius.circular(AppRadii.androidCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Text(
          '주소 인증 주민만 평가를 작성할 수 있습니다.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
        ),
      ),
    );
  }
}
