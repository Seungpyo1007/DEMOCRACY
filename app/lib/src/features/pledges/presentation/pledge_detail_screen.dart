import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/app_timeline.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/bill_overlap.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_report_action.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:democracy/src/features/shared/presentation/source_viewer.dart';
import 'package:democracy/src/features/shell/application/tab_accessory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens an original from the page, with what the viewer's header should
/// say about it.
typedef SourceOpener =
    Future<void> Function(
      BuildContext context,
      Uri url, {
      SourceMetadata? source,
      String? title,
    });

Future<void> _openInApp(
  BuildContext context,
  Uri url, {
  SourceMetadata? source,
  String? title,
}) => openSource(context, url, source: source, title: title);

/// Keys the tests find the page's parts by.
abstract final class PledgeDetailKeys {
  static const sourceDocument = Key('pledge-detail-source-document');
  static const sharedWordBills = Key('pledge-detail-shared-word-bills');
}

/// One pledge, and the record of how it came to carry its status.
///
/// The status is one line near the top on purpose. A verdict with no visible
/// reasoning is the thing the product exists to avoid, so the pipeline that
/// produced it, and the originals it rests on, get the room.
///
/// Everything here opens in the app: the 선거공보 in the PDF reader, other
/// originals in the in-app browser ([openSource]).
class PledgeDetailScreen extends ConsumerWidget {
  const PledgeDetailScreen({required this.pledgeId, this.opener, super.key});

  final String pledgeId;

  /// Opens an original. Defaults to [openSource]; injected by tests.
  final SourceOpener? opener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(pledgeBoardProvider);
    final holder = ref.watch(districtProfileProvider).value?.incumbent;

    final data = board.hasError || !board.hasValue ? null : board.requireValue;
    final pledge = data?.byId(pledgeId);
    final kicker = pledge == null
        ? null
        : [
            if (pledge.category.isNotEmpty) pledge.category,
            ?holder?.name,
          ].join(' · ');

    return Scaffold(
      body: EditorialScrollView(
        // Until the board is in (or when the id is not on it) the page is
        // still a pledge's page, so it keeps a neutral title and its back
        // button rather than going blank.
        title: pledge?.title ?? '공약 상세',
        kicker: kicker == null || kicker.isEmpty ? null : kicker,
        onBack: () => _back(context),
        // Opened over the tracker, the action is already in the tab bar's
        // round button, lent by the tracker below. Opened straight from the
        // home there is no tracker beneath to lend it, so the page floats
        // its own -- the report stays one tap away either way.
        floatingAction:
            tabBarTakesAction(context) &&
                ref.watch(tabAccessoriesProvider).containsKey(TabSlot.tracker)
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
                      children: _detail(
                        context,
                        pledge,
                        bills: holder?.record?.bills,
                        open: opener ?? _openInApp,
                      ),
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

/// The elections whose 선거공보 the NEC files under `/policy_pdf/<선거일>/`.
const _electionsByDay = {'20240410': '제22대 국회의원선거'};

/// What a pledge's source document is, when its URL says: 「제22대
/// 국회의원선거 선거공보」 for a 공보 PDF on policy.nec.go.kr, and null for
/// anything else.
String? brochureTitle(Uri url) {
  if (!url.host.endsWith('nec.go.kr') || !isPdfSource(url)) {
    return null;
  }
  final segments = url.pathSegments;
  final day = segments.length > 1 && segments.first == 'policy_pdf'
      ? segments[1]
      : null;
  final election = _electionsByDay[day];
  return election == null ? '선거공보' : '$election 선거공보';
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

/// The body under the title: the verdict, how it was reached, the originals
/// it rests on, and the incumbent's bills that share its words.
List<Widget> _detail(
  BuildContext context,
  Pledge pledge, {
  required BillRecord? bills,
  required SourceOpener open,
}) {
  final judgement = pledge.judgement;
  final overlaps = bills == null
      ? const <BillOverlap>[]
      : billsSharingKeywords(pledge.title, bills.items);

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
                              onTap: () => open(
                                context,
                                judgement.source.sourceUrl,
                                source: judgement.source,
                                title: '판정문',
                              ),
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
    RevealIn(
      index: 2,
      child: _Originals(pledge: pledge, open: open),
    ),
    if (bills != null && overlaps.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.x6),
      RevealIn(
        index: 3,
        child: _SharedWordBills(overlaps: overlaps, bills: bills),
      ),
    ],
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

/// Section 02: where the pledge comes from, and the originals its status
/// rests on.
///
/// The document is named, with who published it and when it was fetched,
/// above the link to it: most pledges are 「판정 전」, and for those this
/// section is all the app knows about them.
///
/// A reversal's evidence link is refused at parse time when missing, so on
/// the one status where its absence would matter this section always has it.
class _Originals extends StatelessWidget {
  const _Originals({required this.pledge, required this.open});

  final Pledge pledge;
  final SourceOpener open;

  @override
  Widget build(BuildContext context) {
    final reversal = pledge.status == PledgeStatus.reversed;
    final source = pledge.source;
    final brochure = brochureTitle(source.sourceUrl);
    final document = brochure ?? '공약 원문';
    final evidence = pledge.evidenceUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '02', label: '공약 출처'),
        const SizedBox(height: AppSpacing.x1),
        _Fact(label: '문서', value: document),
        _Fact(label: '발행', value: source.publisher),
        _Fact(label: '가져온 날', value: source.asOfLabel),
        _LinkRow(
          key: PledgeDetailKeys.sourceDocument,
          caption: '출처 ${source.publisher} · ${source.asOfLabel}',
          title: brochure == null ? '공약 원문 보기' : '선거공보 원문 보기',
          trailing: '›',
          onTap: () =>
              open(context, source.sourceUrl, source: source, title: document),
        ),
        if (evidence != null)
          _LinkRow(
            caption: reversal ? '번복 근거' : '관련 원문',
            title: reversal ? '원문 대조 보기' : '원문 자세히 보기',
            onTap: () =>
                open(context, evidence, title: reversal ? '번복 근거' : '관련 원문'),
          ),
      ],
    );
  }
}

/// One labelled line of what the page knows about the source document.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      minHeight: 44,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppTextStyles.disclaimer.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.caption,
    required this.title,
    required this.onTap,
    this.trailing = '↗',
    super.key,
  });

  final String caption;
  final String title;
  final VoidCallback onTap;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: RuledRow(
        minHeight: 52,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        onTap: onTap,
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
              trailing,
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

/// Section 03: the incumbent's recent bills whose titles share a word with
/// the pledge's.
///
/// Called a word match in the header and again under it, because that is all
/// it is. A bill naming the same subject has not thereby kept the pledge, and
/// one that does not may still be the one that did; both readings are left
/// to the reader. Drawn only when something matched, so an empty result
/// cannot read as "nothing was done".
class _SharedWordBills extends StatelessWidget {
  const _SharedWordBills({required this.overlaps, required this.bills});

  final List<BillOverlap> overlaps;
  final BillRecord bills;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PledgeDetailKeys.sharedWordBills,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '03', label: '제목이 겹치는 대표 발의 법안'),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '최근 대표 발의 법안 ${bills.total}건 중 공약 제목의 낱말이 법안 제목에도 들어 있는 '
          '법안입니다. 낱말이 겹친다는 뜻일 뿐, 공약 이행 여부를 판단한 결과가 아닙니다.',
          style: AppTextStyles.disclaimer.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: AppSpacing.x1),
        for (final overlap in overlaps)
          RuledRow(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overlap.bill.title,
                  style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (overlap.bill.stage.isNotEmpty) overlap.bill.stage,
                    if (overlap.bill.stamp.isNotEmpty) overlap.bill.stamp,
                    '겹친 낱말 ${overlap.keywords.join(', ')}',
                  ].join(' · '),
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.x2),
        SourceBadge(source: bills.source),
      ],
    );
  }
}
