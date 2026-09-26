import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:flutter/material.dart';

/// One line on a [ResultsLineChart].
class ChartSeries {
  const ChartSeries({
    required this.shares,
    this.color = AppColors.ink,
    this.dashed = false,
  });

  /// Percentages, one per x step.
  final List<double> shares;
  final Color color;

  /// A broken line for a series that is a different kind of thing -- a poll
  /// that is not accredited -- rather than a paler one, which would read as
  /// the same thing with less emphasis.
  final bool dashed;
}

/// Lines that draw themselves in, left to right, with serif labels.
///
/// Written here rather than with `DrawnLine` because the poll comparison needs
/// several series on one scale and a dashed stroke, and rather than with
/// fl_chart because the entrance has to match every other line in the app.
class ResultsLineChart extends StatelessWidget {
  const ResultsLineChart({
    required this.series,
    required this.xLabels,
    this.showValues = false,
    this.height = 160,
    super.key,
  });

  final List<ChartSeries> series;

  /// Under each x step: '2016', '7월 29일'.
  final List<String> xLabels;

  /// Sets each point's share above it. For a single series only; on several
  /// the figures would collide.
  final bool showValues;

  final double height;

  static const _dot = 3.5;
  static const _top = 22.0;
  static const _labelBand = 24.0;

  @override
  Widget build(BuildContext context) {
    final all = [for (final s in series) ...s.shares];
    if (all.isEmpty) {
      return SizedBox(height: height);
    }

    // Padded so the extremes do not sit on the frame, and so a nearly flat
    // series is not stretched into a dramatic one.
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    final pad = math.max(2.0, (hi - lo) * 0.25);
    lo -= pad;
    hi += pad;

    final steps = xLabels.length;
    double x(int i, double width) =>
        _dot + (steps < 2 ? 0.5 : i / (steps - 1)) * (width - _dot * 2);
    double y(double share) =>
        _top + (1 - (share - lo) / (hi - lo)) * (height - _top - _labelBand);

    final labelStyle = AppTextStyles.statLabel.copyWith(
      fontFamily: AppFonts.serif,
      color: AppColors.neutral600,
    );

    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final placed = [
              for (final s in series)
                [
                  for (var i = 0; i < s.shares.length && i < steps; i++)
                    Offset(x(i, width), y(s.shares[i])),
                ],
            ];

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // A hairline baseline, so the labels hang from something.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _labelBand - 4,
                  child: const ColoredBox(
                    color: AppColors.divider,
                    child: SizedBox(height: 1),
                  ),
                ),
                Positioned.fill(
                  child: MotionIn(
                    duration: AppMotion.draw,
                    delay: AppMotion.stagger,
                    curve: AppMotion.drawCurve,
                    builder: (context, t, _) => CustomPaint(
                      painter: _SeriesPainter(
                        series: series,
                        placed: placed,
                        progress: t,
                        dotRadius: showValues ? _dot : 0,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < steps; i++)
                  Positioned(
                    left: x(i, width) - 32,
                    width: 64,
                    bottom: 0,
                    child: Text(
                      xLabels[i],
                      textAlign: i == 0
                          ? TextAlign.left
                          : (i == steps - 1
                                ? TextAlign.right
                                : TextAlign.center),
                      style: labelStyle,
                    ),
                  ),
                if (showValues && series.isNotEmpty)
                  for (var i = 0; i < placed.first.length; i++)
                    Positioned(
                      left: placed.first[i].dx - 32,
                      width: 64,
                      top: placed.first[i].dy - 22,
                      child: RevealIn(
                        index: i + 2,
                        child: Text(
                          series.first.shares[i].toStringAsFixed(1),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.figureSmall.copyWith(
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.series,
    required this.placed,
    required this.progress,
    required this.dotRadius,
  });

  final List<ChartSeries> series;
  final List<List<Offset>> placed;
  final double progress;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    for (var s = 0; s < series.length; s++) {
      final points = placed[s];
      if (points.length < 2) {
        continue;
      }
      final paint = Paint()
        ..color = series[s].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = series[s].dashed ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }

      for (final PathMetric metric in path.computeMetrics()) {
        final end = metric.length * progress;
        if (!series[s].dashed) {
          canvas.drawPath(metric.extractPath(0, end), paint);
          continue;
        }
        for (var d = 0.0; d < end; d += 7) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 4, end)), paint);
        }
      }

      if (dotRadius > 0) {
        final fill = Paint()..color = AppColors.ground;
        for (var i = 0; i < points.length; i++) {
          // A dot appears when the line reaches it, not before.
          if (progress + 1e-6 < i / (points.length - 1)) {
            continue;
          }
          canvas
            ..drawCircle(points[i], dotRadius, fill)
            ..drawCircle(points[i], dotRadius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.progress != progress ||
      old.series != series ||
      old.placed != placed ||
      old.dotRadius != dotRadius;
}

/// The 역대 결과 line: one series, dotted at each election, figures set above.
class HistoricalChart extends StatelessWidget {
  const HistoricalChart({required this.points, super.key});

  final List<HistoricalPoint> points;

  @override
  Widget build(BuildContext context) {
    return ResultsLineChart(
      key: const ValueKey('historical-chart'),
      series: [
        ChartSeries(shares: [for (final p in points) p.share]),
      ],
      xLabels: [for (final p in points) '${p.year}'],
      showValues: true,
    );
  }
}

/// The colour a poll series is drawn in, shared by its line and its legend.
///
/// Accredited series step down the ink ramp by position so three of them can
/// be told apart; an unaccredited one is always the lightest readable step
/// and dashed. None of it is a party colour, and the order is the payload's,
/// so no series is darker for leading.
ChartSeries pollSeriesStyle(PollSeries poll, int index) {
  const ramp = [AppColors.ink, AppColors.neutral700, AppColors.neutral600];
  return ChartSeries(
    shares: [for (final p in poll.points) p.share],
    color: poll.accredited ? ramp[index % ramp.length] : AppColors.neutral600,
    dashed: !poll.accredited,
  );
}

/// The legend swatch for a series: the same stroke as its line.
class SeriesSwatch extends StatelessWidget {
  const SeriesSwatch({required this.series, super.key});

  final ChartSeries series;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 2),
      painter: _SwatchPainter(series.color, dashed: series.dashed),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.color, {required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}
