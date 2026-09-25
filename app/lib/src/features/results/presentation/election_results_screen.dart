import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';
import 'package:democracy/src/features/results/presentation/count_map.dart';
import 'package:democracy/src/features/results/presentation/poll_disclosure_sheet.dart';
import 'package:democracy/src/features/results/presentation/results_charts.dart';
import 'package:democracy/src/features/shared/presentation/embargo_notice.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live counting, with a map that cannot become a map of who is winning.
class ElectionResultsScreen extends ConsumerStatefulWidget {
  const ElectionResultsScreen({super.key});

  @override
  ConsumerState<ElectionResultsScreen> createState() =>
      _ElectionResultsScreenState();
}

class _ElectionResultsScreenState extends ConsumerState<ElectionResultsScreen> {
  String? _selectedId;
  int _segment = 0;

  static const _segments = ['실시간', '역대 결과', '여론조사 비교'];

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(electionResultsProvider);
    final home = ref.watch(addressControllerProvider).district?.id;

    return Scaffold(
      body: results.when(
        loading: () =>
            Center(child: PlatformAdaptiveProgress.circular(context)),
        error: (error, _) => Center(
          child: Text(
            error is NotAvailableException
                ? '개표 정보는 아직 준비 중입니다.'
                : '개표 정보를 불러오지 못했습니다.',
          ),
        ),
        data: (data) {
          final reduced = AppMotion.reduced(context);

          // The LIVE mark says counting is running, which is itself a
          // statement about the count. It rides with the figures and goes
          // with them.
          final live = switch (data.counts) {
            Published(:final value) => value.live,
            Withheld() => false,
          };

          return EditorialScrollView(
            title: '실시간 개표',
            kicker: data.electionName,
            trailing: live ? const _LiveMark() : null,
            slivers: [
              // Only a published count has a national share to state.
              if (data.counts case Published(:final value))
                SliverToBoxAdapter(
                  child: RevealIn(
                    index: 1,
                    child: _OverallCount(counts: value),
                  ),
                ),
              SliverToBoxAdapter(
                child: RevealIn(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.x4,
                      AppSpacing.screen,
                      0,
                    ),
                    // UISegmentedControl on iOS, SegmentedButton on Android:
                    // the one control on the page is the platform's own.
                    child: AppSegmentedControl(
                      segments: _segments,
                      selectedIndex: _segment,
                      onSelected: (index) => setState(() => _segment = index),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: reduced ? Duration.zero : AppMotion.base,
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
                  child: KeyedSubtree(
                    key: ValueKey(_segment),
                    child: switch (_segment) {
                      1 => _Historical(points: data.historical),
                      2 => switch (data.polls) {
                        Published(:final value) => _PollComparison(
                          polls: value,
                        ),
                        Withheld(:final article, :final notice, :final until) =>
                          EmbargoNotice(
                            article: article,
                            notice: notice,
                            headline: '지금은 여론조사 결과를\n표시할 수 없습니다',
                            until: until,
                          ),
                      },
                      // Exhaustive over a sealed type: deleting the withheld
                      // arm is a compile error, not a screen that quietly
                      // publishes a count before the polls close.
                      _ => switch (data.counts) {
                        Published(:final value) => _LiveCount(
                          counts: value,
                          homeId: home,
                          selectedId: _selectedId,
                          onSelected: (district) =>
                              setState(() => _selectedId = district.districtId),
                        ),
                        Withheld(:final article, :final notice, :final until) =>
                          EmbargoNotice(
                            article: article,
                            notice: notice,
                            headline: '지금은 개표 결과를\n표시할 수 없습니다',
                            until: until,
                          ),
                      },
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A still dot, always paired with the word.
///
/// The dot breathes while counting runs -- one of the two things in the app
/// that repeat. The word stays: a dot on its own is a state only a sighted
/// reader who knows the convention can read. Under reduced motion, and in
/// tests, the dot is still.
class _LiveMark extends StatelessWidget {
  const _LiveMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LivePulse(),
        const SizedBox(width: 5),
        Text(
          'LIVE',
          style: AppTextStyles.sectionLabel.copyWith(
            color: AppColors.ink,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// 전국 개표율, set as the figure the screen is about.
class _OverallCount extends StatelessWidget {
  const _OverallCount({required this.counts});

  final CountView counts;

  @override
  Widget build(BuildContext context) {
    // The national share arrives in the same feed as the district counts and
    // carries no provenance of its own, so it is attributed to that feed.
    final source = counts.districts.firstOrNull?.source;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x4,
        AppSpacing.screen,
        0,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.x2 + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '전국 개표율',
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Figure(
                      value: counts.overallCountedShare,
                      fractionDigits: 1,
                      unit: '%',
                      style: AppTextStyles.statValue.copyWith(
                        color: AppColors.ink,
                        fontSize: 56,
                        letterSpacing: -2.2,
                      ),
                      unitStyle: AppTextStyles.figureUnit.copyWith(
                        color: AppColors.ink,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              if (source != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.x1),
                    child: SourceBadge(source: source),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The map with the selected district's count floating over its foot.
class _LiveCount extends StatelessWidget {
  const _LiveCount({
    required this.counts,
    required this.homeId,
    required this.selectedId,
    required this.onSelected,
  });

  final CountView counts;
  final String? homeId;
  final String? selectedId;
  final ValueChanged<DistrictCount> onSelected;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final id = selectedId ?? homeId ?? counts.districts.firstOrNull?.districtId;
    final selected = id == null ? null : counts.byId(id);

    final panel = selected == null
        ? null
        : AnimatedSwitcher(
            duration: AppMotion.reduced(context)
                ? Duration.zero
                : AppMotion.fast,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: _CountPanel(
              key: ValueKey(selected.districtId),
              count: selected,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.x4,
            AppSpacing.screen,
            0,
          ),
          child: CountMap(
            districts: counts.districts,
            selectedId: id,
            homeId: homeId,
            onSelected: onSelected,
          ),
        ),
        if (panel != null)
          if (surface.isGlass)
            // The panel overlaps the map, as the guide draws it: the two are
            // one object, not a map with a list under it. Plain paper rather
            // than a glass stand-in: glass on iOS 26 belongs to the controls,
            // and a painted imitation beside the real thing reads as neither.
            Transform.translate(
              offset: const Offset(0, -22),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: RevealIn(
                  index: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.ground,
                      borderRadius: BorderRadius.circular(
                        AppRadii.iosCardLarge,
                      ),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: panel,
                    ),
                  ),
                ),
              ),
            )
          else
            // Android sets the panel as Material 3's filled card: the
            // container the platform uses for one self-contained reading.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x4,
                AppSpacing.x4,
                AppSpacing.x4,
                0,
              ),
              child: RevealIn(
                index: 3,
                child: Card.filled(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: panel,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _CountPanel extends StatelessWidget {
  const _CountPanel({required this.count, super.key});

  final DistrictCount count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                count.districtName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Text(
              count.countedDisplay,
              style: AppTextStyles.ctaSmall.copyWith(
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3 + 2),
        for (var i = 0; i < count.tallies.length; i++) ...[
          _TallyRow(
            tally: count.tallies[i],
            // Rank by neutral tone, never by party. The leader is darkest
            // because they lead, and that is the only thing the shade says.
            fill: switch (i) {
              0 => AppColors.ink,
              1 => AppColors.neutral600,
              _ => AppColors.neutral400,
            },
            delay: AppMotion.staggerFor(i + 1),
          ),
          const SizedBox(height: AppSpacing.x3 + 2),
        ],
        SourceBadge(source: count.source),
      ],
    );
  }
}

/// Name, party, share, and a bar that only ever grows.
///
/// The high-water mark is the rule `MonotonicBar` keeps, held here because
/// this row sets the name and share above the bar rather than beside it: a
/// share dropping between updates is an out-of-order update, not news.
class _TallyRow extends StatefulWidget {
  const _TallyRow({
    required this.tally,
    required this.fill,
    required this.delay,
  });

  final CandidateTally tally;
  final Color fill;
  final Duration delay;

  @override
  State<_TallyRow> createState() => _TallyRowState();
}

class _TallyRowState extends State<_TallyRow> {
  late double _peak = widget.tally.fraction;

  @override
  void didUpdateWidget(_TallyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tally.name != widget.tally.name) {
      _peak = widget.tally.fraction;
    } else if (widget.tally.fraction > _peak) {
      _peak = widget.tally.fraction;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tally = widget.tally;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                tally.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            PartyTag(party: PartyRef(name: tally.party)),
            const Spacer(),
            Text(
              tally.display,
              style: AppTextStyles.figureSmall.copyWith(color: AppColors.ink),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1 + 2),
        GrowBar(
          fraction: _peak,
          color: widget.fill,
          height: 12,
          delay: widget.delay,
        ),
      ],
    );
  }
}

class _Historical extends StatelessWidget {
  const _Historical({required this.points});

  final List<HistoricalPoint> points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x6,
        AppSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(label: '역대 득표율'),
          const SizedBox(height: AppSpacing.x4),
          if (points.isEmpty)
            Text(
              '표시할 역대 결과가 없습니다.',
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral600,
              ),
            )
          else
            RevealIn(index: 1, child: HistoricalChart(points: points)),
        ],
      ),
    );
  }
}

/// Accredited polls solid, anything else dashed, and labelled either way.
class _PollComparison extends StatelessWidget {
  const _PollComparison({required this.polls});

  final List<PollSeries> polls;

  @override
  Widget build(BuildContext context) {
    final styles = [
      for (var i = 0; i < polls.length; i++) pollSeriesStyle(polls[i], i),
    ];
    final waves = polls.fold<int>(
      0,
      (most, poll) => poll.points.length > most ? poll.points.length : most,
    );
    final longest = polls.firstWhere(
      (poll) => poll.points.length == waves,
      orElse: () => polls.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x6,
        AppSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(label: '조사별 추이'),
          const SizedBox(height: AppSpacing.x4),
          if (polls.isNotEmpty) ...[
            RevealIn(
              index: 1,
              child: ResultsLineChart(
                key: const ValueKey('poll-chart'),
                series: styles,
                xLabels: [for (final p in longest.points) '${p.year}차'],
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < polls.length; i++)
                    RevealIn(
                      index: i + 2,
                      child: _PollLegendRow(series: polls[i], style: styles[i]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
          ],
          // Permanent, and outside the `if`: the distinction has to be stated
          // whether or not a series is on screen to prompt it.
          const DisclaimerBox(
            text: '앱 내 조사는 공인 조사가 아닙니다. 표본과 방법이 공개된 공인 조사와 같은 무게로 읽지 마세요.',
          ),
        ],
      ),
    );
  }
}

/// A series, with the disclosure the law makes inseparable from it.
///
/// 제108조제5항 asks the required items to accompany the published result, so
/// the headline ones are drawn here rather than only behind the tap: a sheet
/// the reader never opens does not accompany anything.
class _PollLegendRow extends StatelessWidget {
  const _PollLegendRow({required this.series, required this.style});

  final PollSeries series;
  final ChartSeries style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${series.caption}, ${series.disclosure.inlineNotice}, 표기사항 보기',
      excludeSemantics: true,
      child: RuledRow(
        onTap: () => PollDisclosureSheet.show(context, series.disclosure),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 22, child: SeriesSwatch(series: style)),
                const SizedBox(width: AppSpacing.x2 + 2),
                Expanded(
                  child: Text(
                    series.caption,
                    style: AppTextStyles.ctaSmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  '표기사항',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.neutral600,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            Padding(
              padding: const EdgeInsets.only(left: 22 + AppSpacing.x2 + 2),
              child: Text(
                series.disclosure.inlineNotice,
                style: AppTextStyles.disclaimer.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
