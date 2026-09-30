import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_report_action.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:democracy/src/features/shell/application/tab_accessory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Keys the tests reach for, because the same words ("↩ 번복", "2건", "38%")
/// legitimately appear in more than one place on this page.
abstract final class PledgeTrackerKeys {
  static const heroRate = ValueKey('pledge-tracker-hero-rate');
  static const legend = ValueKey('pledge-tracker-legend');
  static const listCount = ValueKey('pledge-tracker-list-count');
  static const statusBar = ValueKey('pledge-tracker-status-bar');
  static const notJudgedNote = ValueKey('pledge-tracker-not-judged-note');
}

/// Three zoom levels: the whole distribution, then by category, then one
/// pledge's judgement.
///
/// The order is the argument. A resident who only sees a headline percentage
/// cannot tell whether it was earned; the stacked bar and its table break it
/// into counts, the category bars say where the work went, and the detail
/// says who decided and on what.
///
/// A board with nothing judged yet is only a list: no rate, no bar, no
/// category bars, because each of those would read as a verdict of 0%. It
/// says so once, above the list, with the document the list came from.
class PledgeTrackerScreen extends ConsumerStatefulWidget {
  const PledgeTrackerScreen({super.key});

  @override
  ConsumerState<PledgeTrackerScreen> createState() =>
      _PledgeTrackerScreenState();
}

class _PledgeTrackerScreenState extends ConsumerState<PledgeTrackerScreen> {
  PledgeStatus? _filter;

  /// Tapping the active status again clears it, so the table is its own
  /// reset and there is no separate "all" control to find.
  void _toggleFilter(PledgeStatus status) {
    setState(() => _filter = _filter == status ? null : status);
    PlatformAdaptiveHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(pledgeBoardProvider);
    final district = ref.watch(districtProvider);
    // The name is a courtesy in the kicker, not something the tracker needs,
    // so a profile that has not loaded (or failed) just leaves it out.
    final incumbent = ref.watch(districtProfileProvider).value?.incumbent?.name;
    final kicker = [?incumbent, ?district?.displayName].join(' · ');

    return TabAccessoryScope(
      slot: TabSlot.tracker,
      accessory: tabBarTakesAction(context)
          ? PledgeReportAction.accessory(context, ref)
          : null,
      child: Scaffold(
        body: EditorialScrollView(
          kicker: kicker.isEmpty ? null : kicker,
          title: '공약이행률 트래커',
          // Where the tab bar takes it (native iOS, Android) the action lives in
          // its round button, lent below; elsewhere it floats on the page.
          floatingAction: tabBarTakesAction(context)
              ? null
              : const PledgeReportAction(),
          slivers: [
            // The title stands while the board loads or fails, so only the
            // body below it swaps between states.
            if (_loaded(board) case final data?)
              _Tracker(
                board: data,
                filter: _filter,
                onStatusTapped: _toggleFilter,
              )
            else
              SliverPadding(
                padding: kPagePadding,
                sliver: SliverToBoxAdapter(
                  child: AsyncSection<PledgeBoard>(
                    value: board,
                    onRetry: () => ref.invalidate(pledgeBoardProvider),
                    builder: (context, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The board when there is one to draw, as [AsyncSection] would decide it:
/// an error wins over a stale value, a refresh keeps the value on screen.
PledgeBoard? _loaded(AsyncValue<PledgeBoard> board) =>
    board.hasError || !board.hasValue ? null : board.requireValue;

/// The loaded page, as one padded sliver under the title.
class _Tracker extends StatelessWidget {
  const _Tracker({
    required this.board,
    required this.filter,
    required this.onStatusTapped,
  });

  final PledgeBoard board;
  final PledgeStatus? filter;
  final ValueChanged<PledgeStatus> onStatusTapped;

  @override
  Widget build(BuildContext context) {
    final categories = board.categories;
    final judged = board.hasJudgements;
    final listNumber =
        [
          if (judged) 'overview',
          if (categories.isNotEmpty) 'categories',
        ].length +
        1;

    // One box rather than a lazy list: the page is short, and the list at
    // the bottom has to exist for the legend above it to filter.
    return SliverPadding(
      padding: kPagePadding,
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.x6),
            if (board.countOf(PledgeStatus.notJudged) > 0) ...[
              RevealIn(
                child: _NotJudgedNote(
                  key: PledgeTrackerKeys.notJudgedNote,
                  board: board,
                ),
              ),
              const SizedBox(height: AppSpacing.x6),
            ],
            if (judged) ...[
              RevealIn(
                child: _Overview(
                  board: board,
                  filter: filter,
                  onStatusTapped: onStatusTapped,
                ),
              ),
              const SizedBox(height: AppSpacing.x8 - 4),
            ],
            if (categories.isNotEmpty) ...[
              RevealIn(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(number: '02', label: '분야별'),
                    const SizedBox(height: AppSpacing.x4 - 2),
                    for (var i = 0; i < categories.length; i++) ...[
                      // Kept over promised, and nothing else: see
                      // CategoryRate.share for why partial work earns no
                      // partial credit here.
                      LabeledBar(
                        label: categories[i].category,
                        fraction: categories[i].share,
                        valueText: categories[i].display,
                        labelWidth: 60,
                        delay: AppMotion.staggerFor(i + 2),
                      ),
                      const SizedBox(height: AppSpacing.x4 - 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
            ],
            RevealIn(
              index: 2,
              child: _PledgeList(
                board: board,
                filter: filter,
                number: listNumber.toString().padLeft(2, '0'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one place the page says that nothing, or not everything, has been
/// judged, and where the list came from.
///
/// Stated once and plainly: the pledges are the winner's own words from the
/// 선거공보, and no call has been made on them. The source link is the
/// document itself, so a reader can check every title against it.
class _NotJudgedNote extends StatelessWidget {
  const _NotJudgedNote({required this.board, super.key});

  final PledgeBoard board;

  @override
  Widget build(BuildContext context) {
    final text = board.hasJudgements
        ? '「판정 전」 공약은 아직 이행 여부를 판정하지 않았습니다. '
              '당선인의 선거공보에 실린 공약을 옮겨 적은 것입니다.'
        : '이 공약들은 아직 이행 여부를 판정하지 않았습니다. '
              '당선인의 선거공보에 실린 공약을 옮겨 적은 것입니다.';

    return DisclaimerBox(
      text: text,
      action: SourceBadge(source: board.source),
    );
  }
}

/// Section 01: the headline, the whole distribution as one bar, and the
/// table that names every part of it.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.board,
    required this.filter,
    required this.onStatusTapped,
  });

  final PledgeBoard board;
  final PledgeStatus? filter;
  final ValueChanged<PledgeStatus> onStatusTapped;

  @override
  Widget build(BuildContext context) {
    // Only built when something is judged, so there is a rate to show.
    final percent = (board.fulfilmentRate! * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '01', label: '종합 이행률'),
        const SizedBox(height: AppSpacing.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                key: PledgeTrackerKeys.heroRate,
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Figure(
                  value: percent,
                  unit: '%',
                  style: AppTextStyles.figureHero.copyWith(
                    color: AppColors.ink,
                  ),
                  unitStyle: AppTextStyles.figureUnit.copyWith(
                    color: AppColors.ink,
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x2 + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Figure(
                    value: board.total,
                    unit: '건',
                    delay: AppMotion.staggerFor(2),
                    style: AppTextStyles.figureSmall.copyWith(
                      color: AppColors.ink,
                      fontSize: 26,
                    ),
                    unitStyle: AppTextStyles.figureUnit.copyWith(
                      color: AppColors.ink,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '등록 공약',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4 + 2),
        _StatusBar(key: PledgeTrackerKeys.statusBar, board: board),
        const SizedBox(height: AppSpacing.x2 + 2),
        Column(
          key: PledgeTrackerKeys.legend,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in _shownStatuses(board))
              _LegendRow(
                status: status,
                count: board.countOf(status),
                percent: (board.shareOf(status) * 100).round(),
                selected: filter == status,
                onTap: () => onStatusTapped(status),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SourceBadge(source: board.source)),
            const SizedBox(width: AppSpacing.x3),
            // Descriptive: it says what the reader can do, not what to think.
            const MarginNote('번복은 원문 대조 가능', delay: AppMotion.slow),
          ],
        ),
      ],
    );
  }
}

/// The four verdicts, plus 「판정 전」 when the board has any.
List<PledgeStatus> _shownStatuses(PledgeBoard board) => [
  ...PledgeStatus.verdicts,
  if (board.countOf(PledgeStatus.notJudged) > 0) PledgeStatus.notJudged,
];

/// The distribution as one 100% bar, drawn left to right a status at a time.
///
/// Segments are coloured by [PledgeStatusChip.barColor], which is a ramp of
/// ink with only 번복 in the accent. Colour never carries the meaning alone:
/// the table directly under the bar names each part, and a screen reader gets
/// all four shares in one label.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.board, super.key});

  static const _gap = 2.0;
  static const _height = 28.0;

  final PledgeBoard board;

  @override
  Widget build(BuildContext context) {
    final label = [
      for (final status in _shownStatuses(board))
        '${status.label} ${(board.shareOf(status) * 100).round()}%',
    ].join(', ');
    final present = [
      for (final status in _shownStatuses(board))
        if (board.countOf(status) > 0) status,
    ];

    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gaps = _gap * (present.length - 1).clamp(0, 4);
            final width = (constraints.maxWidth - gaps).clamp(0.0, 1e9);

            return MotionIn(
              duration: AppMotion.slow,
              delay: AppMotion.staggerFor(1),
              curve: Curves.linear,
              builder: (context, t, _) => Row(
                children: [
                  for (var i = 0; i < present.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width:
                          width *
                          board.shareOf(present[i]) *
                          _segmentProgress(t, i, present.length),
                      child: ColoredBox(
                        color: PledgeStatusChip.barColor(present[i]),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Each segment gets its own slice of the timeline, overlapping the next a
  /// little, so the bar reads as filled in order rather than all at once.
  static double _segmentProgress(double t, int index, int count) {
    if (t >= 1) {
      return 1;
    }
    final slice = 1 / count;
    final start = index * slice * 0.85;
    final end = (start + slice * 1.45).clamp(0.0, 1.0);
    final local = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return AppMotion.ink.transform(local);
  }
}

/// One line of the table under the bar, doubling as the list's filter.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.status,
    required this.count,
    required this.percent,
    required this.selected,
    required this.onTap,
  });

  final PledgeStatus status;
  final int count;
  final int percent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : AppMotion.fast,
          curve: AppMotion.settle,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? AppSpacing.x2 : 0,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.neutral100 : Colors.transparent,
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  status.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.ctaSmall.copyWith(
                    color: PledgeStatusChip.textColor(status),
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$count건',
                  textAlign: TextAlign.end,
                  style: AppTextStyles.cardBody.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.end,
                  style: AppTextStyles.badge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.neutral600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last section: every pledge, or only those with the status picked
/// above. It is 03 under the distribution and the category bars, and moves up
/// when a list-only board has neither.
class _PledgeList extends StatelessWidget {
  const _PledgeList({
    required this.board,
    required this.filter,
    required this.number,
  });

  final PledgeBoard board;
  final PledgeStatus? filter;
  final String number;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final shown = filter == null
        ? board.pledges
        : board.pledges.where((pledge) => pledge.status == filter).toList();
    // Keyed by the filter so the switcher treats each filter's list as a new
    // child. Reduced motion skips the switcher and AnimatedSize altogether: a
    // zero-length AnimatedSize still re-lays itself out mid-layout.
    final rows = Column(
      key: ValueKey(filter),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final pledge in shown) _PledgeRow(pledge: pledge)],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: number,
          label: filter == null ? '전체 공약' : '${filter!.label} 공약',
          trailing: Text(
            '${shown.length}건',
            key: PledgeTrackerKeys.listCount,
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
            ),
          ),
        ),
        if (reduced)
          rows
        else
          // The list changes length with the filter, so the height eases to
          // its new size while the rows cross-fade, instead of the page below
          // jumping.
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.settle,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              reverseDuration: AppMotion.leave,
              switchInCurve: AppMotion.settle,
              switchOutCurve: AppMotion.settle,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: rows,
            ),
          ),
      ],
    );
  }
}

class _PledgeRow extends StatelessWidget {
  const _PledgeRow({required this.pledge});

  final Pledge pledge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${pledge.title}, ${pledge.status.label}',
      excludeSemantics: true,
      child: RuledRow(
        onTap: () => context.push(AppRoutes.pledgeDetail(pledge.id)),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                pledge.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.disclaimer.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                pledge.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardBody.copyWith(
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            PledgeStatusChip(status: pledge.status),
          ],
        ),
      ),
    );
  }
}
