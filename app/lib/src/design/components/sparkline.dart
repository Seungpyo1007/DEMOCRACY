import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A figure's recent shape, drawn small.
///
/// Ink, not the accent: this is a record, and the accent is reserved for the
/// brand and for one data meaning that is not this one. The line carries no
/// judgement about whether the trend is good.
class Sparkline extends StatelessWidget {
  const Sparkline({required this.series, this.height = 64, super.key});

  final ActivitySeries series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (low, high) = series.bounds;

    return Semantics(
      // A line chart is invisible to a screen reader, so the same information
      // is spelled out. The endpoints and the range are what the shape says.
      label:
          '${series.points.first.label}부터 ${series.points.last.label}까지 '
          '최저 ${series.minimum.round()}${series.unit}, '
          '최고 ${series.maximum.round()}${series.unit}, '
          '최근 ${series.latestDisplay}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: low,
            maxY: high,
            minX: 0,
            maxX: (series.points.length - 1).toDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= series.points.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        series.points[index].label,
                        style: AppTextStyles.statLabel.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < series.points.length; i++)
                    FlSpot(i.toDouble(), series.points[i].value),
                ],
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.ink,
                barWidth: 2,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: index == series.points.length - 1 ? 3 : 0,
                        color: AppColors.ink,
                        strokeWidth: 0,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.neutral200.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
