import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_report_action.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// One pledge, and the record of how it came to carry its status.
///
/// The status is one line near the top on purpose. A verdict with no visible
/// reasoning is the thing the product exists to avoid, so the pipeline that
/// produced it, and the originals it rests on, get the room.
class PledgeDetailScreen extends ConsumerWidget {
  const PledgeDetailScreen({required this.pledgeId, super.key});

  final String pledgeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(pledgeBoardProvider);
    final incumbent = ref.watch(districtProfileProvider).value?.incumbent.name;

    final data = board.hasError || !board.hasValue ? null : board.requireValue;
    final pledge = data?.byId(pledgeId);
    final kicker = pledge == null
        ? null
        : [
            if (pledge.category.isNotEmpty) pledge.category,
            ?incumbent,
          ].join(' · ');

    return Scaffold(
      body: EditorialScrollView(
        // Until the board is in (or when the id is not on it) the page is
        // still a pledge's page, so it keeps a neutral title and its back
        // button rather than going blank.
        title: pledge?.title ?? '공약 상세',
        kicker: kicker == null || kicker.isEmpty ? null : kicker,
        onBack: () => _back(context),
        // On native iOS the action lives in the tab bar's accessory (lent
        // by the tracker below); everywhere else it floats on the page.
        floatingAction: usesNativeIosControls(context)
            ? null
            : const PledgeReportAction(),
        slivers: [
          SliverPadding(
            padding: kPagePadding,
            sliver: data == null
                ? SliverToBoxAdapter(
                    child: AsyncSection<PledgeBoard>(
                      value: board,
                      onRetry: () => ref.invalidate(pledgeBoardProvider),
                      builder: (context, _) => const SizedBox.shrink(),
                    ),
                  )
                : pledge == null
                ? const SliverToBoxAdapter(child: _NotFound())
                : SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _detail(pledge),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

void _back(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  }
}

Future<void> _open(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.screen),
      child: Text(
        '이 지역구에서 해당 공약을 찾지 못했습니다.',
        style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
      ),
    );
  }
}

/// The body under the title: the verdict, how it was reached, and the
/// originals it rests on.
List<Widget> _detail(Pledge pledge) {
  final judgement = pledge.judgement;

  return [
    const SizedBox(height: AppSpacing.x3 + 2),
    RevealIn(child: _Verdict(status: pledge.status)),
    const SizedBox(height: AppSpacing.x8 - 4),
    RevealIn(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(number: '01', label: '판정 과정'),
          const SizedBox(height: AppSpacing.x4 + 2),
          if (!pledge.status.isJudged)
            const DisclaimerBox(
              text: '아직 이행 여부를 판정하지 않은 공약입니다. 공약 내용은 아래 원문에서 확인할 수 있습니다.',
            )
          else if (judgement == null)
            const DisclaimerBox(
              text: '이 공약은 아직 판정 기록이 없습니다. 상태는 원문 출처에서 가져온 값입니다.',
            )
          else ...[
            AppTimeline(
              steps: [
                for (var i = 0; i < judgement.steps.length; i++)
                  TimelineStep(
                    title: judgement.steps[i].actor,
                    detail: judgement.steps[i].detail,
                    stamp: judgement.steps[i].stamp,
                    // The decision itself is the last step, so that is
                    // where its written reasoning hangs.
                    evidence: i == judgement.steps.length - 1
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextLink(
                              label: '판정문 보기 →',
                              onTap: () => _open(judgement.source.sourceUrl),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            SourceBadge(source: judgement.source),
          ],
        ],
      ),
    ),
    const SizedBox(height: AppSpacing.x6),
    RevealIn(index: 2, child: _Originals(pledge: pledge)),
    // There is no verdict to ground on a pledge nobody has judged.
    if (pledge.status.isJudged) ...[
      const SizedBox(height: AppSpacing.x4),
      const Align(
        alignment: AlignmentDirectional.centerStart,
        child: MarginNote('판정 근거는 모두 원문으로 연결됩니다', delay: AppMotion.slow),
      ),
    ],
  ];
}

/// `현재 판정` and the status, between hairlines.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.status});

  final PledgeStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 + 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '현재 판정',
                style: AppTextStyles.badge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.neutral600,
                ),
              ),
            ),
            PledgeStatusChip(status: status, large: true),
          ],
        ),
      ),
    );
  }
}

/// Section 02: the originals the status rests on.
///
/// A reversal's evidence link is refused at parse time when missing, so on
/// the one status where its absence would matter this section always has it.
class _Originals extends StatelessWidget {
  const _Originals({required this.pledge});

  final Pledge pledge;

  @override
  Widget build(BuildContext context) {
    final reversal = pledge.status == PledgeStatus.reversed;
    final source = pledge.source;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '02', label: '관련 원문'),
        const SizedBox(height: AppSpacing.x1),
        if (pledge.evidenceUrl != null)
          _LinkRow(
            caption: reversal ? '번복 근거' : '관련 원문',
            title: reversal ? '원문 대조 보기' : '원문 자세히 보기',
            url: pledge.evidenceUrl!,
          ),
        _LinkRow(
          caption: '출처 ${source.publisher} · ${source.asOfLabel}',
          title: '공약 원문',
          url: source.sourceUrl,
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.caption,
    required this.title,
    required this.url,
  });

  final String caption;
  final String title;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: RuledRow(
        minHeight: 52,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        onTap: () => _open(url),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.disclaimer.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: AppTextStyles.cardBody.copyWith(
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Text(
              '↗',
              style: AppTextStyles.disclaimer.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
