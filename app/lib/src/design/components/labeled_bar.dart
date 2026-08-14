import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// A named quantity drawn as a bar: label, track, value.
///
/// The same three-column row appears five times across the guide -- category
/// fulfilment, AI match scores, the four review axes, vote share, and the
/// onboarding interest slider's track. They differ only in column widths, bar
/// height and fill colour, so they are one widget rather than five.
///
/// Only the track shape is platform-adaptive, and it is the reverse of what
/// you would guess: the guide draws these square on iOS and rounded on
/// Android.
class LabeledBar extends StatelessWidget {
  const LabeledBar({
    required this.label,
    required this.fraction,
    required this.valueText,
    this.fillColor,
    this.labelWidth = 52,
    this.valueWidth = 32,
    this.trackHeight = 10,
    this.duration = Duration.zero,
    super.key,
  });

  /// The tracker's category bars fill once, over 800ms, and never animate
  /// again. Everything else is drawn at rest.
  static const fillDuration = Duration(milliseconds: 800);
  static const fillCurve = Curves.easeOut;

  final String label;

  /// 0..1. Clamped, because a score out of range is a data problem that
  /// should not become a layout problem.
  final double fraction;

  final String valueText;
  final Color? fillColor;
  final double labelWidth;
  final double valueWidth;
  final double trackHeight;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = surface.isGlass
        ? BorderRadius.zero
        : BorderRadius.circular(trackHeight / 2);
    final clamped = fraction.clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              height: trackHeight,
              child: ColoredBox(
                color: AppColors.neutral200,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: duration == Duration.zero ? clamped : 0,
                      end: clamped,
                    ),
                    duration: duration,
                    curve: fillCurve,
                    // heightFactor is not optional here: a ColoredBox has no
                    // child to take a height from, so without it the fill
                    // collapses to nothing and the track renders empty.
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value,
                      heightFactor: 1,
                      child: ColoredBox(color: fillColor ?? AppColors.ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.badge.copyWith(color: AppColors.ink),
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
      duration: const Duration(milliseconds: 400),
    );
  }
}
