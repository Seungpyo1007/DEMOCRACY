import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:flutter/material.dart';

/// A figure's recent shape, drawn small, and drawn in when it appears.
///
/// Straight segments between observations rather than a smoothed curve: a
/// curve invents values between the months. Ink, not the accent: this is a record, and the accent is reserved for the
/// brand and for one data meaning that is not this one. The line carries no
/// judgement about whether the trend is good.
class Sparkline extends StatelessWidget {
  const Sparkline({required this.series, this.height = 64, super.key});

  final ActivitySeries series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (low, high) = series.bounds;
    final span = high - low == 0 ? 1 : high - low;
    final count = series.points.length;

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
        child: Column(
          children: [
            Expanded(
              child: DrawnLine(
                dotRadius: 3,
                points: [
                  for (var i = 0; i < count; i++)
                    Offset(
                      count == 1 ? 0.5 : i / (count - 1),
                      (series.points[i].value - low) / span,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final point in series.points)
                  Text(
                    point.label,
                    style: AppTextStyles.disclaimer.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
