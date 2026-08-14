import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One candidate's shape across the reader's interest areas.
///
/// The accent fill is the one place a match result borrows the brand colour,
/// and it is translucent so it reads as an overlay on a grid rather than as a
/// filled area with a value of its own. There is deliberately no second
/// candidate drawn on top: overlaying two would invite a winner-loser reading
/// of a chart that is only about fit with the reader.
class MatchRadar extends StatelessWidget {
  const MatchRadar({
    required this.axes,
    this.onAxisTapped,
    this.size = 200,
    super.key,
  });

  final List<MatchAxis> axes;
  final ValueChanged<MatchAxis>? onAxisTapped;
  final double size;

  @override
  Widget build(BuildContext context) {
    // fl_chart's radar needs at least three points to have an area at all.
    if (axes.length < 3) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: [
        '관심 분야별 부합도',
        for (final axis in axes) '${axis.label} ${axis.display}점',
      ].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: size,
        child: RadarChart(
          RadarChartData(
            radarShape: RadarShape.polygon,
            radarBackgroundColor: Colors.transparent,
            radarBorderData: const BorderSide(color: AppColors.neutral300),
            gridBorderData: const BorderSide(color: AppColors.neutral200),
            tickBorderData: const BorderSide(color: Colors.transparent),
            // The rings are a grid, not data. Labelling them invites reading
            // the chart as a measurement when it is a fit.
            ticksTextStyle: const TextStyle(color: Colors.transparent),
            tickCount: 3,
            titlePositionPercentageOffset: 0.15,
            titleTextStyle: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
            ),
            getTitle: (index, angle) =>
                RadarChartTitle(text: axes[index].label, angle: 0),
            radarTouchData: RadarTouchData(
              enabled: onAxisTapped != null,
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions) {
                  return;
                }
                final index = response?.touchedSpot?.touchedRadarEntryIndex;
                if (index == null || index < 0 || index >= axes.length) {
                  return;
                }
                onAxisTapped?.call(axes[index]);
              },
            ),
            dataSets: [
              RadarDataSet(
                fillColor: AppColors.radarFill,
                borderColor: AppColors.signal,
                borderWidth: 2,
                entryRadius: 2,
                dataEntries: [
                  for (final axis in axes) RadarEntry(value: axis.score),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
