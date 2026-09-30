import 'dart:math' as math;

import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:flutter/material.dart';

/// The winner's vote share at each decided election, as a self-drawing line.
///
/// The axis is snapped to whole tens around the data rather than run from
/// zero: the differences between elections are a few points, and a 0-100
/// axis would draw them as a flat line. The gridline labels say where the
/// axis starts, so the crop is visible rather than hidden.
class WinnerShareChart extends StatelessWidget {
  const WinnerShareChart({required this.rows, super.key});

  /// Decided elections, oldest first.
  final List<ElectionRow> rows;

  static const height = 182.0;

  /// Where the top and bottom gridlines sit. The gap above the top one is
  /// room for a value label on a point that reaches the ceiling.
  static const _plotTop = 30.0;
  static const _plotBottom = 150.0;
  static const _sideInset = 30.0;
  static const _dot = 4.5;

  static String formatShare(double share) => '${share.toStringAsFixed(1)}%';

  /// Semantics for the whole figure: the chart is read as its values.
  String get semanticsLabel =>
      '당선 득표율 ${rows.map((r) => '${r.year}년 ${formatShare(r.share!)}').join(', ')}';

  (double, double) get _bounds {
    final shares = rows.map((r) => r.share!);
    final low = (shares.reduce(math.min) / 10).floorToDouble() * 10;
    var high = (shares.reduce(math.max) / 10).ceilToDouble() * 10;
    if (high <= low) {
      high = low + 10;
    }
    return (low, high);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final (low, high) = _bounds;
    final axisStyle = AppTextStyles.disclaimer.copyWith(
      fontSize: 10,
      color: AppColors.neutral600,
    );

    return Semantics(
      label: semanticsLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final plotWidth = width - _sideInset * 2;

            double xFor(int i) => rows.length == 1
                ? width / 2
                : _sideInset + plotWidth * i / (rows.length - 1);
            double fractionFor(double share) => (share - low) / (high - low);
            double yFor(double share) =>
                _plotBottom - (_plotBottom - _plotTop) * fractionFor(share);

            final points = [
              for (var i = 0; i < rows.length; i++)
                Offset(
                  rows.length == 1 ? 0.5 : i / (rows.length - 1),
                  fractionFor(rows[i].share!),
                ),
            ];

            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final (y, color) in [
                  (_plotTop, AppColors.divider),
                  ((_plotTop + _plotBottom) / 2, AppColors.divider),
                  (_plotBottom, AppColors.neutral400),
                ])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y,
                    height: 1,
                    child: ColoredBox(color: color),
                  ),
                Positioned(
                  right: 0,
                  bottom: height - _plotTop + 2,
                  child: Text('${high.round()}%', style: axisStyle),
                ),
                Positioned(
                  right: 0,
                  bottom: height - _plotBottom + 2,
                  child: Text('${low.round()}%', style: axisStyle),
                ),
                // DrawnLine insets its points by the dot radius, so its box is
                // grown by the same amount to land them on the gridlines.
                Positioned(
                  left: (rows.length == 1 ? width / 2 : _sideInset) - _dot,
                  width: (rows.length == 1 ? 0 : plotWidth) + _dot * 2,
                  top: _plotTop - _dot,
                  height: _plotBottom - _plotTop + _dot * 2,
                  child: DrawnLine(points: points, dotRadius: _dot),
                ),
                for (var i = 0; i < rows.length; i++) ...[
                  Positioned(
                    left: xFor(i) - 40,
                    width: 80,
                    top: yFor(rows[i].share!) - 30,
                    child: _ValueLabel(
                      text: formatShare(rows[i].share!),
                      // Each figure is written in once the line reaches it.
                      delay:
                          AppMotion.draw *
                          (rows.length == 1 ? 0 : i / (rows.length - 1)),
                    ),
                  ),
                  Positioned(
                    left: xFor(i) - 50,
                    width: 100,
                    top: height - 20,
                    child: Text(
                      '${rows[i].year} · ${rows[i].term}대',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: AppTextStyles.disclaimer.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({required this.text, required this.delay});

  final String text;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return MotionIn(
      delay: delay,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        style: AppTextStyles.figureSmall.copyWith(
          fontSize: 15,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
