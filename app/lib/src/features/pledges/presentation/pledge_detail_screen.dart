import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// One pledge, and the record of how it came to carry its status.
///
/// The status chip is the smallest part of this screen on purpose. A verdict
/// with no visible reasoning is the thing the product exists to avoid, so the
/// pipeline that produced it gets the room.
class PledgeDetailScreen extends ConsumerWidget {
  const PledgeDetailScreen({required this.pledgeId, super.key});

  final String pledgeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(pledgeBoardProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PlatformAdaptiveAppBar.of(context, title: '공약 상세'),
      body: AsyncSection<PledgeBoard>(
        value: board,
        onRetry: () => ref.invalidate(pledgeBoardProvider),
        builder: (context, data) {
          final pledge = data.byId(pledgeId);
          if (pledge == null) {
            return const _NotFound();
          }
          return _Detail(pledge: pledge);
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Text(
          '이 지역구에서 해당 공약을 찾지 못했습니다.',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.pledge});

  final Pledge pledge;

  @override
  Widget build(BuildContext context) {
    final judgement = pledge.judgement;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screen),
      children: [
        if (pledge.category.isNotEmpty) ...[
          MicroLabel(pledge.category),
          const SizedBox(height: 3),
        ],
        Text(pledge.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.x3),
        Align(
          alignment: Alignment.centerLeft,
          child: PledgeStatusChip(status: pledge.status),
        ),
        const SizedBox(height: AppSpacing.x3),
        SourceBadge(source: pledge.source),

        if (pledge.evidenceUrl != null) ...[
          const SizedBox(height: AppSpacing.x4),
          _EvidenceLink(url: pledge.evidenceUrl!, status: pledge.status),
        ],

        const SizedBox(height: AppSpacing.x8),
        const SectionLabel('판정 파이프라인'),
        const SizedBox(height: AppSpacing.x3),
        if (judgement == null)
          const DisclaimerBox(
            text: '이 공약은 아직 판정 기록이 없습니다. 상태는 원문 출처에서 가져온 값입니다.',
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTimeline(
                  steps: [
                    for (final step in judgement.steps)
                      TimelineStep(
                        title: step.actor,
                        detail: step.detail,
                        stamp: step.stamp,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3),
                const Divider(height: 1, color: AppColors.neutral200),
                const SizedBox(height: AppSpacing.x2),
                SourceBadge(source: judgement.source),
              ],
            ),
          ),
      ],
    );
  }
}

/// The link back to the original wording.
///
/// Required for a reversal and refused at parse time without it, so this is
/// never absent on the one status where its absence would matter.
class _EvidenceLink extends StatelessWidget {
  const _EvidenceLink({required this.url, required this.status});

  final Uri url;
  final PledgeStatus status;

  @override
  Widget build(BuildContext context) {
    final reversal = status == PledgeStatus.reversed;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reversal ? '번복 근거' : '관련 원문',
            style: AppTextStyles.badge.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            reversal
                ? '무엇이 어떻게 바뀌었는지 원문에서 확인할 수 있습니다.'
                : '원문에서 자세한 내용을 확인할 수 있습니다.',
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(height: AppSpacing.x2),
          Semantics(
            link: true,
            child: InkWell(
              onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.ink),
                  const SizedBox(width: AppSpacing.x1),
                  Text(
                    '원문 대조 보기',
                    style: AppTextStyles.ctaSmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
