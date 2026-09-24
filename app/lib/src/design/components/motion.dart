import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// Runs a 0-to-1 progress once, after [delay], and hands it to [builder].
///
/// The building block for every entrance in the app. It exists so each
/// animated widget does not grow its own controller, delay timer and
/// reduced-motion check -- and so they all agree on what "reduced" means: the
/// end state, drawn on the first frame.
class MotionIn extends StatefulWidget {
  const MotionIn({
    required this.builder,
    this.duration = AppMotion.standard,
    this.delay = Duration.zero,
    this.curve = AppMotion.standardCurve,
    this.child,
    super.key,
  });

  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Widget? child;

  @override
  State<MotionIn> createState() => _MotionInState();
}

class _MotionInState extends State<MotionIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final total = widget.duration + widget.delay;
    _controller = AnimationController(vsync: this, duration: total);
    // The delay is folded into one controller as a leading interval rather
    // than a timer, so there is nothing to cancel if the widget leaves early.
    final start = total == Duration.zero
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: widget.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) {
      return;
    }
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) =>
          widget.builder(context, _progress.value, child),
      child: widget.child,
    );
  }
}

/// Fades a child in and lifts it 12dp into place.
///
/// Give siblings consecutive [index]es and they arrive one after another.
class RevealIn extends StatelessWidget {
  const RevealIn({required this.child, this.index = 0, super.key});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return MotionIn(
      delay: AppMotion.staggerFor(index),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// Eases a child's height to its new size, or does nothing under reduced
/// motion.
///
/// Not [AnimatedSize] with a zero duration: that asserts ("was mutated in its
/// own performLayout") the first time the child changes size. Under reduced
/// motion the wrapper is simply left out.
class MotionSize extends StatelessWidget {
  const MotionSize({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return child;
    }
    return AnimatedSize(
      duration: AppMotion.standard,
      curve: AppMotion.standardCurve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// A figure that counts up from zero to [value] when it first appears, and
/// from its old value to its new one when [value] changes.
///
/// Screen readers get the final value only. An announcement that walks
/// through every intermediate number would be noise, and one read mid-count
/// would be wrong.
class CountUp extends StatelessWidget {
  const CountUp({
    required this.value,
    required this.style,
    this.fractionDigits = 0,
    this.unit,
    this.unitStyle,
    this.delay = Duration.zero,
    super.key,
  });

  final num value;
  final TextStyle style;
  final int fractionDigits;

  /// Set smaller than the figure, directly after it: `%`, `건`, `점`.
  final String? unit;
  final TextStyle? unitStyle;
  final Duration delay;

  String _format(double v) => v.toStringAsFixed(fractionDigits);

  @override
  Widget build(BuildContext context) {
    final target = value.toDouble();
    final label = '${_format(target)}${unit ?? ''}';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: MotionIn(
        duration: AppMotion.data,
        delay: delay,
        curve: AppMotion.dataCurve,
        builder: (context, t, _) {
          return TweenAnimationBuilder<double>(
            // Once the entrance has run, a later change animates from where
            // the figure stands rather than from zero again.
            tween: Tween(end: target * t),
            duration: t < 1 ? Duration.zero : AppMotion.standard,
            curve: AppMotion.dataCurve,
            builder: (context, shown, _) => Text.rich(
              TextSpan(
                text: _format(shown),
                style: style,
                children: [
                  if (unit != null)
                    TextSpan(text: unit, style: unitStyle ?? style),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A horizontal bar that grows to [fraction] of its track.
///
/// Square-ended on purpose: a rounded end reads as a UI control, a square one
/// as a quantity.
class GrowBar extends StatelessWidget {
  const GrowBar({
    required this.fraction,
    this.color = AppColors.ink,
    this.trackColor = AppColors.neutral100,
    this.height = 10,
    this.delay = Duration.zero,
    super.key,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double height;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final target = fraction.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: trackColor,
        child: MotionIn(
          duration: AppMotion.data,
          delay: delay,
          curve: AppMotion.dataCurve,
          // After the entrance, a new value animates from the old one instead
          // of snapping -- the live count grows in place.
          builder: (context, t, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: target * t),
            duration: t < 1 ? Duration.zero : AppMotion.standard,
            curve: AppMotion.dataCurve,
            builder: (context, shown, _) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: shown,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pen stroke under a margin note, drawn left to right as if written.
///
/// The wobble is fixed, not random, so goldens are stable and the same note
/// looks the same every time it is drawn.
class HandUnderline extends StatelessWidget {
  const HandUnderline({
    this.width,
    this.color = AppColors.handwriting,
    this.delay = Duration.zero,
    super.key,
  });

  /// Null takes the width the parent gives it, which is how a margin note
  /// underlines exactly its own text.
  final double? width;
  final Color color;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MotionIn(
        duration: AppMotion.draw,
        delay: delay,
        curve: AppMotion.drawCurve,
        builder: (context, t, _) => SizedBox(
          width: width ?? double.infinity,
          height: 8,
          child: CustomPaint(
            painter: _UnderlinePainter(progress: t, color: color),
          ),
        ),
      ),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  _UnderlinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(2, size.height * 0.62)
      ..cubicTo(
        w * 0.25,
        size.height * 0.1,
        w * 0.6,
        size.height,
        w - 2,
        size.height * 0.35,
      );
    _drawPartial(canvas, path, progress, _stroke(color, 2.2));
  }

  @override
  bool shouldRepaint(_UnderlinePainter old) =>
      old.progress != progress || old.color != color;
}

/// A line through [points] (each 0..1 in both axes, y up) that draws itself.
///
/// Used by the sparklines and the history chart. Points are normalised by
/// the caller so this knows nothing about what the axis means.
class DrawnLine extends StatelessWidget {
  const DrawnLine({
    required this.points,
    this.color = AppColors.ink,
    this.strokeWidth = 2,
    this.dotRadius = 0,
    this.delay = Duration.zero,
    super.key,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  /// Zero for a sparkline; set it to mark each observation.
  final double dotRadius;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return MotionIn(
      duration: AppMotion.draw,
      delay: delay,
      curve: AppMotion.drawCurve,
      builder: (context, t, _) => CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(
          points: points,
          progress: t,
          color: color,
          strokeWidth: strokeWidth,
          dotRadius: dotRadius,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.dotRadius,
  });

  final List<Offset> points;
  final double progress;
  final Color color;
  final double strokeWidth;
  final double dotRadius;

  Offset _place(Offset p, Size size) {
    final inset = math.max(dotRadius, strokeWidth / 2);
    return Offset(
      inset + p.dx * (size.width - inset * 2),
      inset + (1 - p.dy) * (size.height - inset * 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    final placed = [for (final p in points) _place(p, size)];
    final path = Path()..moveTo(placed.first.dx, placed.first.dy);
    for (final p in placed.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    _drawPartial(canvas, path, progress, _stroke(color, strokeWidth));

    if (dotRadius > 0) {
      final fill = Paint()..color = AppColors.ground;
      final ring = _stroke(color, strokeWidth);
      for (var i = 0; i < placed.length; i++) {
        // A dot appears when the line reaches it, not before.
        final reachedAt = i / (placed.length - 1);
        if (progress + 1e-6 < reachedAt) {
          continue;
        }
        canvas
          ..drawCircle(placed[i], dotRadius, fill)
          ..drawCircle(placed[i], dotRadius, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.points != points ||
      old.strokeWidth != strokeWidth ||
      old.dotRadius != dotRadius;
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _drawPartial(Canvas canvas, Path path, double progress, Paint paint) {
  if (progress <= 0) {
    return;
  }
  if (progress >= 1) {
    canvas.drawPath(path, paint);
    return;
  }
  final metrics = path.computeMetrics().toList();
  final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
  var remaining = total * progress;
  for (final PathMetric metric in metrics) {
    if (remaining <= 0) {
      break;
    }
    final length = math.min(remaining, metric.length);
    canvas.drawPath(metric.extractPath(0, length), paint);
    remaining -= length;
  }
}
