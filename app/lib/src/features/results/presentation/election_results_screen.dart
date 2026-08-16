import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';
import 'package:democracy/src/features/results/presentation/count_map.dart';
import 'package:democracy/src/features/shared/presentation/embargo_notice.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:fl_chart/fl_chart.dart';
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

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(electionResultsProvider);
    final home = ref.watch(addressControllerProvider).district?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(child: Text('개표 정보를 불러오지 못했습니다.')),
        data: (data) {
          // Exhaustive over a sealed type: deleting the withheld arm is a
          // compile error, not a screen that quietly publishes a count before
          // the polls close.
          final counts = switch (data.counts) {
            Published(:final value) => value,
            Withheld() => null,
          };
          final selectedId =
              _selectedId ?? home ?? counts?.districts.firstOrNull?.districtId;
          final selected = selectedId == null ? null : counts?.byId(selectedId);

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _Header(results: data),
              switch (data.counts) {
                Published(:final value) => CountMap(
                  districts: value.districts,
                  selectedId: selectedId,
                  homeId: home,
                  onSelected: (district) =>
                      setState(() => _selectedId = district.districtId),
                ),
                Withheld(:final article, :final notice) => EmbargoNotice(
                  article: article,
                  notice: notice,
                ),
              },
              Transform.translate(
                // The panel overlaps the map, as the guide draws it: the two
                // are one object, not a map with a list under it.
                offset: const Offset(0, -22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3 + 2,
                  ),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selected != null) _CountPanel(count: selected),
                        const SizedBox(height: AppSpacing.x3),
                        AppSegmentedControl(
                          segments: const ['실시간', '역대 결과', '여론조사 비교'],
                          selectedIndex: _segment,
                          onSelected: (index) =>
                              setState(() => _segment = index),
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        switch (_segment) {
                          1 => _HistoricalChart(points: data.historical),
                          2 => switch (data.polls) {
                            Published(:final value) => _PollComparison(
                              polls: value,
                            ),
                            Withheld(:final article, :final notice) =>
                              EmbargoNotice(article: article, notice: notice),
                          },
                          _ => const SizedBox.shrink(),
                        },
                      ],
                    ),
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

class _Header extends StatelessWidget {
  const _Header({required this.results});

  final ElectionResults results;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x3,
          AppSpacing.screen,
          AppSpacing.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('실시간 개표', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  results.header,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                // The LIVE dot says counting is running, which is itself a
                // statement about the count. It rides with the figures.
                if (results.counts case Published(
                  value: final counts,
                ) when counts.live) ...[
                  const SizedBox(width: AppSpacing.x2),
                  const _LiveDot(),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulses, and is always paired with the word.
///
/// A dot on its own is a state only a sighted reader who knows the convention
/// can read.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.signal,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x1),
        Text(
          'LIVE',
          // accent700, not Signal. The design system tunes Signal against the
          // page to 3:1 -- enough for the dot beside this, which is chrome --
          // and says outright to use a deep ramp step for text at paragraph
          // size. This label is 10px.
          style: AppTextStyles.badge.copyWith(color: AppColors.accent700),
        ),
      ],
    );
  }
}

class _CountPanel extends StatelessWidget {
  const _CountPanel({required this.count});

  final DistrictCount count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${count.districtName} · ${count.countedDisplay}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        SourceBadge(source: count.source),
        const SizedBox(height: AppSpacing.x3),
        for (var i = 0; i < count.tallies.length; i++) ...[
          MonotonicBar(
            label: count.tallies[i].name,
            fraction: count.tallies[i].fraction,
            valueText: count.tallies[i].display,
            // Rank by neutral tone, never by party. The leader is darkest
            // because they lead, and that is the only thing the shade says.
            fillColor: switch (i) {
              0 => AppColors.ink,
              1 => AppColors.neutral500,
              _ => AppColors.neutral400,
            },
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
      ],
    );
  }
}

class _HistoricalChart extends StatelessWidget {
  const _HistoricalChart({required this.points});

  final List<HistoricalPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('역대 득표율'),
        const SizedBox(height: AppSpacing.x3),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: 35,
              maxY: 55,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${points[index].year}',
                        style: AppTextStyles.statLabel.copyWith(
                          color: AppColors.neutral500,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].share),
                  ],
                  color: AppColors.ink,
                  barWidth: 2,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Accredited polls solid, this app's dotted, and labelled either way.
class _PollComparison extends StatelessWidget {
  const _PollComparison({required this.polls});

  final List<PollSeries> polls;

  @override
  Widget build(BuildContext context) {
    if (polls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('여론조사 비교'),
        const SizedBox(height: AppSpacing.x3),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: 38,
              maxY: 55,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                for (final series in polls)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < series.points.length; i++)
                        FlSpot(i.toDouble(), series.points[i].share),
                    ],
                    color: series.accredited
                        ? AppColors.ink
                        : AppColors.neutral500,
                    barWidth: 2,
                    // Dashed, not just paler. A weight difference reads as
                    // emphasis; a broken line reads as a different kind of
                    // thing, which is what it is.
                    dashArray: series.accredited ? null : [4, 3],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        for (final series in polls) ...[
          Row(
            children: [
              SizedBox(
                width: 22,
                child: CustomPaint(
                  size: const Size(22, 2),
                  painter: _LegendLine(accredited: series.accredited),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                series.caption,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
        ],
        const SizedBox(height: AppSpacing.x2),
        const DisclaimerBox(
          text: '앱 내 조사는 공인 조사가 아닙니다. 표본과 방법이 공개된 공인 조사와 같은 무게로 읽지 마세요.',
        ),
      ],
    );
  }
}

class _LegendLine extends CustomPainter {
  const _LegendLine({required this.accredited});

  final bool accredited;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accredited ? AppColors.ink : AppColors.neutral500
      ..strokeWidth = 2;

    if (accredited) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 4).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendLine oldDelegate) =>
      oldDelegate.accredited != accredited;
}
