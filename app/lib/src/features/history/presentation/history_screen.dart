import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/history/application/history_providers.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:democracy/src/features/history/presentation/history_timeline.dart';
import 'package:democracy/src/features/history/presentation/winner_share_chart.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The district's history: the place, its elections, its representative.
///
/// Three parts from three publishers, each closed by its own source line. The
/// page is one scroll with a segmented control pinned under the title, because
/// a reader usually comes for one of the three and should not have to scroll
/// past the others to find it -- nor back up to the top to switch.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  /// The anchor segments, in page order.
  static const sections = ['지역', '선거', '의원'];

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scroll = ScrollController();
  final _anchors = [for (final _ in HistoryScreen.sections) GlobalKey()];
  var _active = 0;

  /// Set while a segment's scroll is running, so the scroll listener does not
  /// flick the selection through every section it passes on the way.
  var _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackActive);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_trackActive)
      ..dispose();
    super.dispose();
  }

  /// The offset at which [index]'s section header sits at the top of what
  /// is left visible. On Android the viewport already takes the pinned
  /// chrome (collapsed app bar, segmented bar) off the top. On iOS the
  /// switch floats in the tool row over the page instead, so the section
  /// stops below that row rather than under it.
  double? _offsetOf(int index) {
    final box = _anchors[index].currentContext?.findRenderObject();
    if (box == null || !box.attached) {
      return null;
    }
    final glass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;
    final floating = glass
        ? MediaQuery.paddingOf(context).top +
              EditorialScrollView.iosToolbarExtent
        : 0.0;
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset -
        floating;
  }

  void _trackActive() {
    if (_jumping || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    var active = 0;
    // The last section may be too short to ever reach the top; at the end of
    // the page it is the one being read.
    if (position.pixels >= position.maxScrollExtent - 1 &&
        position.maxScrollExtent > 0) {
      active = _anchors.length - 1;
    } else {
      final threshold = position.pixels + position.viewportDimension / 3;
      for (var i = 0; i < _anchors.length; i++) {
        final offset = _offsetOf(i);
        if (offset != null && offset <= threshold) {
          active = i;
        }
      }
    }
    if (active != _active) {
      setState(() => _active = active);
    }
  }

  Future<void> _jumpTo(int index) async {
    final offset = _offsetOf(index);
    if (offset == null || !_scroll.hasClients) {
      return;
    }
    PlatformAdaptiveHaptics.selection();
    setState(() => _active = index);
    final position = _scroll.position;
    final target = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _jumping = true;
    try {
      if (AppMotion.reduced(context)) {
        _scroll.jumpTo(target);
      } else {
        await _scroll.animateTo(
          target,
          duration: AppMotion.slow,
          curve: AppMotion.sheet,
        );
      }
    } finally {
      _jumping = false;
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(historyRecordProvider);
    await ref.read(historyRecordProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final district = ref.watch(districtProvider);
    final record = ref.watch(historyRecordProvider);
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: EditorialScrollView(
          controller: _scroll,
          title: '역사',
          kicker: district?.displayName,
          note: '한 지역구가 걸어온 길',
          bottomPadding: AppSpacing.x12,
          // iOS: the section switch rides in the floating tool row. Android
          // pins it under the app bar below.
          toolbarCenter: record.hasValue
              ? AppSegmentedControl(
                  segments: HistoryScreen.sections,
                  selectedIndex: _active,
                  onSelected: _jumpTo,
                )
              : null,
          slivers: [
            // Only once there are sections to jump to.
            if (record.hasValue && !surface.isGlass)
              SliverPersistentHeader(
                pinned: true,
                delegate: _AnchorBarDelegate(
                  active: _active,
                  onSelected: _jumpTo,
                  // Android's app bar already pins over the status bar; on
                  // iOS nothing does, so the bar makes its own room there.
                  statusInset: surface.isGlass
                      ? MediaQuery.paddingOf(context).top
                      : 0,
                ),
              ),
            // One box rather than a lazy list: the segments scroll to
            // sections that may be far below the fold, and their offsets are
            // only known once they are laid out.
            SliverPadding(
              padding: kPagePadding,
              sliver: SliverToBoxAdapter(
                child: AsyncSection<HistoryRecord>(
                  value: record,
                  onRetry: () => ref.invalidate(historyRecordProvider),
                  builder: (context, data) =>
                      _HistoryBody(record: data, anchors: _anchors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The segmented control, pinned on paper under the title.
///
/// On iOS the bar reserves [statusInset] of paper: at rest the control sits
/// at the top of its box with the room below it, and as it pins the control
/// slides down into that room so it ends up under the status bar, not
/// beneath it.
class _AnchorBarDelegate extends SliverPersistentHeaderDelegate {
  _AnchorBarDelegate({
    required this.active,
    required this.onSelected,
    required this.statusInset,
  });

  final int active;
  final ValueChanged<int> onSelected;
  final double statusInset;

  static const _bar = 52.0;

  @override
  double get minExtent => _bar + statusInset;

  @override
  double get maxExtent => _bar + statusInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final drop = shrinkOffset.clamp(0.0, statusInset);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ground,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent || shrinkOffset > 0
                ? AppColors.divider
                : AppColors.ground,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: drop),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: _bar,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: Center(
                child: AppSegmentedControl(
                  segments: HistoryScreen.sections,
                  selectedIndex: active,
                  onSelected: onSelected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_AnchorBarDelegate oldDelegate) =>
      active != oldDelegate.active ||
      statusInset != oldDelegate.statusInset ||
      onSelected != oldDelegate.onSelected;
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.record, required this.anchors});

  final HistoryRecord record;
  final List<GlobalKey> anchors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.x2),
        RevealIn(
          child: _RegionSection(region: record.region, anchor: anchors[0]),
        ),
        const SizedBox(height: AppSpacing.x8),
        RevealIn(
          index: 1,
          child: _ElectionSection(record: record, anchor: anchors[1]),
        ),
        const SizedBox(height: AppSpacing.x8),
        RevealIn(
          index: 2,
          child: switch (record.legislator) {
            final legislator? => _LegislatorSection(
              legislator: legislator,
              anchor: anchors[2],
            ),
            null => _EmptySeatSection(
              vacancy: record.vacancy,
              anchor: anchors[2],
            ),
          },
        ),
      ],
    );
  }
}

class _RegionSection extends StatelessWidget {
  const _RegionSection({required this.region, required this.anchor});

  final RegionTimeline region;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(key: anchor, number: '01', label: '지역의 역사'),
        const SizedBox(height: AppSpacing.x4),
        HistoryTimeline(
          entries: [
            for (final event in region.events)
              HistoryTimelineEntry(
                mark: event.year?.toString(),
                title: event.title,
                detail: event.detail,
              ),
          ],
        ),
        SourceBadge(source: region.source),
      ],
    );
  }
}

class _ElectionSection extends StatelessWidget {
  const _ElectionSection({required this.record, required this.anchor});

  final HistoryRecord record;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    final elections = record.elections;
    final firstWin = record.incumbentFirstWinYear;
    final newestFirst = elections.rows.reversed.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          key: anchor,
          number: '02',
          label: '선거의 역사',
          trailing: Text(
            '당선 득표율',
            style: AppTextStyles.disclaimer.copyWith(
              color: AppColors.neutral600,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        WinnerShareChart(rows: elections.decided),
        const SizedBox(height: AppSpacing.x2),
        const Divider(height: 1, thickness: 1, color: AppColors.divider),
        for (var i = 0; i < newestFirst.length; i++)
          RevealIn(
            index: i,
            child: _ElectionRowView(
              row: newestFirst[i],
              index: i,
              firstWin:
                  firstWin != null &&
                  newestFirst[i].year == firstWin &&
                  newestFirst[i].winner?.id == record.legislator?.id,
            ),
          ),
        const SizedBox(height: AppSpacing.x2),
        SourceBadge(source: elections.source),
        if (elections.basis != null) SourceLine(elections.basis!),
      ],
    );
  }
}

class _ElectionRowView extends StatelessWidget {
  const _ElectionRowView({
    required this.row,
    required this.index,
    required this.firstWin,
  });

  final ElectionRow row;
  final int index;

  /// Whether this is the incumbent's first win here. Descriptive only: it is
  /// read off the rows, not a judgement of them.
  final bool firstWin;

  @override
  Widget build(BuildContext context) {
    final term = SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            row.termLabel,
            style: AppTextStyles.figureSmall.copyWith(
              fontSize: 16,
              color: AppColors.ink,
            ),
          ),
          Text(
            '${row.year}',
            style: AppTextStyles.disclaimer.copyWith(
              color: AppColors.neutral600,
            ),
          ),
        ],
      ),
    );
    final nameStyle = AppTextStyles.cardBody.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    );
    final figureStyle = AppTextStyles.figureSmall.copyWith(
      color: AppColors.ink,
    );

    if (row.ongoing) {
      return Semantics(
        link: true,
        hint: '개표 화면으로 이동',
        child: RuledRow(
          minHeight: 58,
          onTap: () => context.go(AppRoutes.results),
          child: Row(
            children: [
              term,
              const SizedBox(width: 10),
              Expanded(child: Text('개표 중', style: nameStyle)),
              ExcludeSemantics(child: Text('→', style: figureStyle)),
            ],
          ),
        ),
      );
    }

    final winner = row.winner!;
    return RuledRow(
      minHeight: 58,
      child: Row(
        children: [
          term,
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.x2,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(winner.name, style: nameStyle),
                PartyTag(party: winner.party),
                if (firstWin)
                  const MarginNote('첫 당선', underline: false, fontSize: 20),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Figure(
            value: row.share!,
            fractionDigits: 1,
            unit: '%',
            delay: AppMotion.staggerFor(index),
            style: figureStyle,
            unitStyle: figureStyle,
          ),
        ],
      ),
    );
  }
}

/// Section 03 when nobody holds the seat. With a [vacancy] the assembly's
/// member list says so, and the section says 「현재 공석」 with that list as
/// its source; without one the feed could not tell, and the section says only
/// that the record is not ready. Neither guesses at a reason.
class _EmptySeatSection extends StatelessWidget {
  const _EmptySeatSection({required this.vacancy, required this.anchor});

  final SeatVacancy? vacancy;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    final vacancy = this.vacancy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(key: anchor, number: '03', label: '의원 연대기'),
        const SizedBox(height: AppSpacing.x4),
        if (vacancy != null) ...[
          Text(
            '현재 공석',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            '국회의원 명단에 이 지역구 의원이 없습니다.',
            style: AppTextStyles.cardBody.copyWith(
              fontSize: 13,
              color: AppColors.neutral600,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          SourceBadge(source: vacancy.source),
        ] else
          Text(
            '의원 정보는 아직 준비 중입니다.',
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
          ),
      ],
    );
  }
}

class _LegislatorSection extends StatelessWidget {
  const _LegislatorSection({required this.legislator, required this.anchor});

  final LegislatorChronicle legislator;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(key: anchor, number: '03', label: '의원 연대기'),
        const SizedBox(height: AppSpacing.x3 + 2),
        Row(
          children: [
            GrayscalePortrait(
              name: legislator.name,
              imageUrl: legislator.portraitUrl,
              width: 48,
              height: 60,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legislator.name,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      PartyTag(party: legislator.party),
                      if (legislator.summary.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          legislator.summary,
                          style: AppTextStyles.cardBody.copyWith(
                            fontSize: 13,
                            color: AppColors.neutral600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4 + 2),
        HistoryTimeline(
          entries: [
            for (final event in legislator.events)
              HistoryTimelineEntry(
                mark: event.mark,
                title: event.title,
                detail: event.detail,
              ),
          ],
        ),
        SourceBadge(source: legislator.source),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextLink(
            label: '전체 의정 기록 →',
            onTap: () => context.go(AppRoutes.home),
          ),
        ),
      ],
    );
  }
}
