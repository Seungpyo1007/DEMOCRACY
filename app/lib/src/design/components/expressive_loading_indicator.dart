/// Material 3 Expressive's loading indicator, for Android.
///
/// A rounded shape that turns continuously and, every 650ms, springs into
/// the next of seven Material shapes -- soft burst, 9-sided cookie,
/// pentagon, pill, sunny, 4-sided cookie, oval -- turning a further quarter
/// as it does. The contained variant sits the same shape in a
/// primaryContainer circle, for places it lands on top of content.
///
/// Follows androidx's `LoadingIndicator.kt` (compose material3): the same
/// shape sequence, the 48dp box with a 38dp active shape, the 4666ms turn,
/// the 650ms morph on a spring of damping 0.6 and stiffness 200, and the
/// same scale-to-fit for shapes that sweep wider as they rotate. The shapes
/// and the morph between them are `material_new_shapes`, a port of
/// androidx's graphics-shapes.
///
/// Where Compose runs the morph off a coroutine loop, this derives every
/// frame from one clock: the morph index, its spring progress and both
/// rotations are functions of the time elapsed. One [Ticker] means
/// [TickerMode] can pause it, and a still frame is just time zero -- which
/// is what reduced motion and tests get.
library;

import 'dart:math' as math;

import 'package:democracy/src/design/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    this.size = defaultSize,
    this.color,
    this.contained = false,
    this.containerColor,
    this.running = true,
    super.key,
  });

  /// The box, as in the spec: 48dp, with the shape 38dp inside it.
  static const defaultSize = 48.0;

  /// The square the indicator takes. The shape is scaled with it, keeping
  /// the spec's 38:48.
  final double size;

  /// The shape's colour. Null is primary, or onPrimaryContainer when
  /// [contained].
  final Color? color;

  /// Whether the shape sits in a filled circle.
  final bool contained;

  /// The circle's colour when [contained]. Null is primaryContainer.
  final Color? containerColor;

  /// False holds the first frame: a pull not yet let go.
  final bool running;

  /// The shape sequence, from `LoadingIndicatorDefaults.IndeterminateIndicatorPolygons`.
  static final List<RoundedPolygon> polygons = [
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ];

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Time already shown before the ticker last started, so a pause and a
  /// resume carry on from the same shape rather than starting over.
  Duration _base = Duration.zero;
  Duration _elapsed = Duration.zero;

  void _tick(Duration sinceStart) {
    setState(() => _elapsed = _base + sinceStart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ExpressiveLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) _sync();
  }

  void _sync() {
    final run = widget.running && AppMotion.loops(context);
    if (run && !_ticker.isActive) {
      _base = _elapsed;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = CustomPaint(
      painter: _MorphPainter(
        frame: _Frame.at(_elapsed),
        color:
            widget.color ??
            (widget.contained ? colors.onPrimaryContainer : colors.primary),
      ),
    );
    return SizedBox.square(
      dimension: widget.size,
      child: widget.contained
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: widget.containerColor ?? colors.primaryContainer,
                shape: const CircleBorder(),
              ),
              child: shape,
            )
          : shape,
    );
  }
}

/// What one moment of the animation draws.
@immutable
class _Frame {
  const _Frame(this.morph, this.progress, this.degrees);

  /// Compose waits [_morphInterval] per shape; each morph starts from rest
  /// at 0 and springs to 1 (with an overshoot the path clamps away), then
  /// snaps back to 0 on the next pair while the rotation target advances a
  /// quarter -- so the end of one morph is the start of the next.
  factory _Frame.at(Duration elapsed) {
    final ms = elapsed.inMicroseconds / 1000;
    final step = ms ~/ _morphInterval;
    final within = (ms - step * _morphInterval) / 1000;
    final progress = SpringSimulation(
      _spring,
      0,
      1,
      0,
    ).x(within).clamp(0.0, 1.0);
    final target = (90.0 + 90.0 * step) % 360;
    final global = (ms % _globalRotation) / _globalRotation * 360;
    return _Frame(
      step % ExpressiveLoadingIndicator.polygons.length,
      progress,
      progress * 90 + target + global,
    );
  }

  /// Which morph of the circular sequence is under way, and how far.
  final int morph;
  final double progress;

  /// The whole rotation, clockwise.
  final double degrees;

  static const _morphInterval = 650;
  static const _globalRotation = 4666;

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 0.6,
  );
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({required this.frame, required this.color});

  final _Frame frame;
  final Color color;

  static const _activeRatio = 38 / 48;

  /// Each shape pair, made once: building a [Morph] matches the two
  /// outlines' features, which is the expensive part.
  static final List<Morph> _morphs = [
    for (var i = 0; i < ExpressiveLoadingIndicator.polygons.length; i++)
      Morph(
        ExpressiveLoadingIndicator.polygons[i],
        ExpressiveLoadingIndicator.polygons[(i + 1) %
            ExpressiveLoadingIndicator.polygons.length],
      ),
  ];

  /// Shrinks every shape enough that none is clipped as it turns: the
  /// ratio of each one's bounds to the bounds it sweeps when rotated, as in
  /// Compose's `calculateScaleFactor`. The larger of the two axes, so a
  /// pill's long side does not shrink everything else.
  static final double _fit = ExpressiveLoadingIndicator.polygons.fold(1.0, (
    fit,
    polygon,
  ) {
    final b = polygon.calculateBounds();
    final m = polygon.calculateMaxBounds();
    final x = (b[2] - b[0]) / (m[2] - m[0]);
    final y = (b[3] - b[1]) / (m[3] - m[1]);
    return math.min(fit, math.max(x, y));
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _fit * _activeRatio;
    final path = _morphs[frame.morph]
        .toPath(progress: frame.progress)
        .transform(
          Matrix4.diagonal3Values(
            size.width * scale,
            size.height * scale,
            1,
          ).storage,
        );
    final centre = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(frame.degrees * math.pi / 180)
      ..translate(-centre.dx, -centre.dy)
      ..drawPath(
        path.shift(centre - path.getBounds().center),
        Paint()..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.frame.morph != frame.morph ||
      old.frame.progress != frame.progress ||
      old.frame.degrees != frame.degrees ||
      old.color != color;
}
