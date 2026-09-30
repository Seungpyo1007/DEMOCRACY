/// The app's loading marks, in place of the platform spinners.
///
/// All of them are the 기표 도장 the app opens with. [InkRingIndicator] is
/// its ring, written from the top and erased from where it began: it stands
/// in for a loading section ([InkLoadingSection]) and fits a small place --
/// a search field, a row. [InkStampIndicator] draws the whole stamp, for
/// the waits that run to seconds: a whole screen, the on-device model.
///
/// None of them shows for the first [appearDelay]: most loads here are a
/// cache away, and a mark that flashes for a tenth of a second is worse
/// than none. With reduced motion (and in tests) they stand still, drawn
/// faintly, and each is read out as 불러오는 중.
library;

import 'dart:math' as math;

import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// How long a load runs before any mark appears.
const appearDelay = Duration(milliseconds: 250);

/// A section still loading: the ring, centred in the room the section
/// will take.
class InkLoadingSection extends StatelessWidget {
  const InkLoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.x8),
      child: Center(child: InkRingIndicator(size: 24)),
    );
  }
}

/// The stamp's ring, written from the top and erased from where it began.
class InkRingIndicator extends StatelessWidget {
  const InkRingIndicator({
    this.size = 20,
    this.color = AppColors.ink,
    this.delayed = true,
    this.active = true,
    super.key,
  });

  final double size;
  final Color color;

  /// False where the reader asked for the wait (a pull to refresh), so the
  /// ring answers at once rather than after [appearDelay].
  final bool delayed;

  /// False draws the ring still and whole: a pull not yet let go.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _Appear(
      delay: delayed ? appearDelay : Duration.zero,
      child: _InkLoop(
        period: const Duration(milliseconds: 1400),
        enabled: active,
        builder: (context, phase, moving) {
          double start;
          double end;
          if (!moving) {
            (start, end) = (0, 1);
          } else if (phase < 0.5) {
            (start, end) = (0, AppMotion.writeCurve.transform(phase / 0.5));
          } else if (phase < 0.58) {
            (start, end) = (0, 1);
          } else {
            (start, end) = (
              AppMotion.writeCurve.transform((phase - 0.58) / 0.42),
              1,
            );
          }
          return Opacity(
            opacity: moving ? 1 : 0.45,
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _RingPainter(start: start, end: end, color: color),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pull to refresh, with the ring in place of the platform's spinner.
///
/// The ring shows still and faint while the page is pulled, whole once the
/// pull would refresh, and turns while the refresh runs.
class InkRefresh extends StatefulWidget {
  const InkRefresh({required this.onRefresh, required this.child, super.key});

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  State<InkRefresh> createState() => _InkRefreshState();
}

class _InkRefreshState extends State<InkRefresh> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final shown = switch (status) {
      RefreshIndicatorStatus.drag ||
      RefreshIndicatorStatus.armed ||
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh => true,
      _ => false,
    };
    final pulled = status != RefreshIndicatorStatus.drag;
    final reduced = AppMotion.reduced(context);

    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) {
            if (mounted) setState(() => _status = status);
          },
          child: widget.child,
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + AppSpacing.x12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: shown ? (pulled ? 1 : 0.6) : 0,
              duration: reduced ? Duration.zero : AppMotion.fast,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.ground,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x2),
                    child: shown
                        ? InkRingIndicator(
                            size: 22,
                            delayed: false,
                            active: status == RefreshIndicatorStatus.refresh,
                          )
                        : const SizedBox.square(dimension: 22),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The whole 기표 도장, drawn as at launch and faded, over and over.
///
/// For waits of seconds -- the on-device model reading a district's
/// pledges -- where a small ring would look stuck.
class InkStampIndicator extends StatelessWidget {
  const InkStampIndicator({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return _Appear(
      child: _InkLoop(
        period: const Duration(milliseconds: 2600),
        builder: (context, phase, moving) {
          double part(double from, double to) {
            if (phase <= from) return 0;
            if (phase >= to) return 1;
            return AppMotion.writeCurve.transform((phase - from) / (to - from));
          }

          final opacity = !moving
              ? 0.5
              : phase < 0.8
              ? 1.0
              : phase < 0.96
              ? 1 - AppMotion.settle.transform((phase - 0.8) / 0.16)
              : 0.0;
          return Opacity(
            opacity: opacity,
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: moving
                    ? StampStrokes(
                        ring: part(0, 0.34),
                        stem: part(0.31, 0.48),
                        branch: part(0.46, 0.58),
                      )
                    : const StampStrokes(ring: 1, stem: 1, branch: 1),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The 기표 도장 as three strokes, each drawn up to its fraction.
///
/// Same geometry as the app icon, in a 100-unit square: a ring of radius 27
/// at the centre, a stem from 30 to 70, and a short stroke from the stem's
/// middle up and to the right, all 6 units wide with round ends.
class StampStrokes extends CustomPainter {
  const StampStrokes({
    required this.ring,
    required this.stem,
    required this.branch,
  });

  final double ring;
  final double stem;
  final double branch;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    final ink = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(50, 50), radius: 27),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        ink,
      );
    }
    if (stem > 0) {
      canvas.drawLine(const Offset(50, 30), Offset(50, 30 + 40 * stem), ink);
    }
    if (branch > 0) {
      canvas.drawLine(
        const Offset(50, 50),
        Offset(50 + 15 * branch, 50 - 8 * branch),
        ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StampStrokes old) =>
      old.ring != ring || old.stem != stem || old.branch != branch;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  final double start;
  final double end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sweep = end - start;
    if (sweep <= 0) return;
    final stroke = size.shortestSide * 0.11;
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      -math.pi / 2 + 2 * math.pi * start,
      2 * math.pi * sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.start != start || old.end != end || old.color != color;
}

/// Holds its child back for [appearDelay], then fades it in.
///
/// A controller rather than a timer, so a test that ends mid-wait is not
/// left with one pending.
class _Appear extends StatefulWidget {
  const _Appear({required this.child, this.delay = appearDelay});

  final Widget child;
  final Duration delay;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final Duration _total = widget.delay + AppMotion.fast;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds / _total.inMilliseconds,
      1,
      curve: AppMotion.settle,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '불러오는 중',
      liveRegion: true,
      child: ExcludeSemantics(
        child: FadeTransition(opacity: _opacity, child: widget.child),
      ),
    );
  }
}

/// Repeats [builder]'s phase over [period] while motion is allowed; stands
/// still (moving false) with reduced motion and in tests.
class _InkLoop extends StatefulWidget {
  const _InkLoop({
    required this.period,
    required this.builder,
    this.enabled = true,
  });

  final Duration period;
  final bool enabled;
  final Widget Function(BuildContext context, double phase, bool moving)
  builder;

  @override
  State<_InkLoop> createState() => _InkLoopState();
}

class _InkLoopState extends State<_InkLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  bool _moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_InkLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    _moving = widget.enabled && AppMotion.loops(context);
    if (_moving) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
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
      animation: _controller,
      builder: (context, _) =>
          widget.builder(context, _controller.value, _moving),
    );
  }
}
