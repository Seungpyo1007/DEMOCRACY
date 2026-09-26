import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/material.dart';

/// A named quantity drawn as a bar: label, track, value.
///
/// The same three-column row appears five times across the guide -- category
/// fulfilment, AI match scores, the four review axes, vote share, and the
/// onboarding interest slider's track. They differ only in column widths, bar
/// height and fill colour, so they are one widget rather than five.
///
/// The bar grows to its value when it first appears.
class LabeledBar extends StatelessWidget {
  const LabeledBar({
    required this.label,
    required this.fraction,
    required this.valueText,
    this.fillColor,
    this.labelWidth = 52,
    this.valueWidth = 40,
    this.trackHeight = 10,
    this.delay = Duration.zero,
    super.key,
  });

  final String label;

  /// 0..1. Clamped, because a score out of range is a data problem that
  /// should not become a layout problem.
  final double fraction;

  final String valueText;
  final Color? fillColor;
  final double labelWidth;
  final double valueWidth;
  final double trackHeight;

  /// Stagger for a stack of bars, so they fill one after another.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
          ),
        ),
        const SizedBox(width: AppSpacing.x2 + 2),
        // Square on both platforms: a quantity, not a control.
        Expanded(
          child: GrowBar(
            fraction: fraction,
            color: fillColor ?? AppColors.ink,
            height: trackHeight,
            delay: delay,
          ),
        ),
        const SizedBox(width: AppSpacing.x2 + 2),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.figureSmall.copyWith(
              color: AppColors.ink,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

/// A bar that only ever grows.
///
/// Vote counts rise as ballots are counted; a candidate's share dropping
/// between polls is a rendering artefact of an out-of-order update, not news.
/// The guide asks for increase-only rendering, so this holds the high-water
/// mark rather than following the input down.
class MonotonicBar extends StatefulWidget {
  const MonotonicBar({
    required this.label,
    required this.fraction,
    required this.valueText,
    this.fillColor,
    this.labelWidth = 64,
    this.valueWidth = 40,
    this.trackHeight = 14,
    super.key,
  });

  final String label;
  final double fraction;
  final String valueText;
  final Color? fillColor;
  final double labelWidth;
  final double valueWidth;
  final double trackHeight;

  @override
  State<MonotonicBar> createState() => _MonotonicBarState();
}

class _MonotonicBarState extends State<MonotonicBar> {
  late double _peak = widget.fraction;

  @override
  void didUpdateWidget(MonotonicBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fraction > _peak) {
      _peak = widget.fraction;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabeledBar(
      label: widget.label,
      fraction: _peak,
      valueText: widget.valueText,
      fillColor: widget.fillColor,
      labelWidth: widget.labelWidth,
      valueWidth: widget.valueWidth,
      trackHeight: widget.trackHeight,
    );
  }
}
