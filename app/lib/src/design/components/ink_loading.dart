/// The app's loading marks.
///
/// Two, by what is waited on:
///
/// * [InkLoadingRows] stands in for a section: ruled rows the height of the
///   content's own, with a short ink stroke written across each. The
///   content arrives into the same rows, so nothing below it moves.
/// * [InkStampIndicator] draws the 기표 도장 the app opens with, then lets
///   it fade, over and over: for a whole screen, the on-device model, a
///   pull to refresh, a pressed button.
///
/// That is the iOS page. Android shows Material 3 Expressive's
/// [ExpressiveLoadingIndicator] instead -- the morphing shape on its own,
/// contained in a circle for pull to refresh, and small beside still
/// placeholder rows -- because there it is the system's loading language,
/// the way the tab bar and buttons already are. Which one is drawn follows
/// [ThemeData.platform], so tests and goldens pick a platform the same way
/// they do for every other adaptive widget.
///
/// Neither shows for the first [appearDelay] unless the reader asked for
/// the wait: most loads here are a cache away, and a mark that flashes for
/// a tenth of a second is worse than none. With reduced motion (and in
/// tests) they stand still, drawn faintly, and each is read out as
/// 불러오는 중.
library;

import 'dart:math' as math;

import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';

/// How long a load runs before any mark appears.
const appearDelay = Duration(milliseconds: 250);

/// Whether this context draws Material's indicators rather than the ink.
bool _material(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform != TargetPlatform.iOS && platform != TargetPlatform.macOS;
}

/// A section's placeholder: [rows] ruled rows with an ink stroke each.
class InkLoadingRows extends StatelessWidget {
  const InkLoadingRows({this.rows = 3, this.rowHeight = 54, super.key});

  final int rows;

  /// [RuledRow]'s own minimum, so the content lands on the same lines.
  final double rowHeight;

  /// Stroke lengths, as a fraction of the row: uneven, like lines of text.
  static const _lengths = [0.62, 0.78, 0.48, 0.7, 0.56, 0.66];

  static const _period = Duration(milliseconds: 2400);

  /// Android's indicator beside the rows: two-thirds of the spec's 48, so
  /// it marks the section without outweighing the rows themselves.
  static const _rowIndicatorSize = 32.0;

  @override
  Widget build(BuildContext context) {
    if (_material(context)) return _materialRows(context);
    return _Appear(
      child: _InkLoop(
        period: _period,
        builder: (context, phase, moving) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows; i++)
              SizedBox(
                height: rowHeight,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _stroke(
                      moving ? _offset(phase, i) : null,
                      _lengths[i % _lengths.length],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Android: the same ruled rows, held still in the placeholder colour,
  /// with a small loading indicator at the end of the first.
  ///
  /// Material 3 has no shimmer or written-in placeholder of its own; the
  /// loading indicator is its mark for a wait. The rows stay so the content
  /// still lands on its own lines, but they no longer move: one moving
  /// thing per section, or the strokes and the shape read as two loads.
  /// The indicator sits in the first row's free end, where no stroke
  /// reaches, so neither is drawn over the other.
  Widget _materialRows(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return _Appear(
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows; i++)
                SizedBox(
                  height: rowHeight,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: _lengths[i % _lengths.length],
                        child: SizedBox(
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: placeholder,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            height: rowHeight,
            child: const Center(
              child: ExpressiveLoadingIndicator(size: _rowIndicatorSize),
            ),
          ),
        ],
      ),
    );
  }

  /// Row [i]'s own phase: each starts [AppMotion.stagger] after the last.
  static double _offset(double phase, int i) {
    final lag = AppMotion.stagger.inMilliseconds / _period.inMilliseconds;
    return (phase - lag * i) % 1;
  }

  /// Written left to right, held, then faded out before the next line.
  /// [phase] null is the still, faint mark.
  static Widget _stroke(double? phase, double length) {
    double width;
    double opacity;
    if (phase == null) {
      width = 1;
      opacity = 0.55;
    } else if (phase < 0.4) {
      width = AppMotion.writeCurve.transform(phase / 0.4);
      opacity = 1;
    } else if (phase < 0.62) {
      width = 1;
      opacity = 1;
    } else if (phase < 0.9) {
      width = 1;
      opacity = 1 - AppMotion.settle.transform((phase - 0.62) / 0.28);
    } else {
      width = 0;
      opacity = 0;
    }
    return FractionallySizedBox(
      widthFactor: length * width,
      child: Opacity(
        opacity: opacity,
        child: const SizedBox(
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.neutral300,
              borderRadius: BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole 기표 도장, drawn as at launch and faded, over and over.
///
/// On Android this is Material 3 Expressive's [ExpressiveLoadingIndicator]
/// instead, in the theme's primary unless [color] is given.
class InkStampIndicator extends StatelessWidget {
  const InkStampIndicator({
    this.size = 28,
    this.color,
    this.delayed = true,
    this.active = true,
    this.contained = false,
    super.key,
  });

  /// The stamp's square. On Android, 40 or more takes the spec's 48dp box;
  /// anything smaller is an inline mark -- in a button, beside a line of
  /// text -- and the shape is fitted to it.
  final double size;

  /// The ink, or the shape's colour on Android. Null is [AppColors.ink] on
  /// iOS and the theme's primary on Android.
  final Color? color;

  /// Android only: the shape in its primaryContainer circle, for where it
  /// lands on top of content. iOS's stamp has nothing behind it either way.
  final bool contained;

  /// False where the reader asked for the wait (a pull, a pressed button),
  /// so the stamp answers at once rather than after [appearDelay].
  final bool delayed;

  /// False draws the stamp still and whole: a pull not yet let go.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final delay = delayed ? appearDelay : Duration.zero;
    if (_material(context)) {
      return _Appear(
        delay: delay,
        child: ExpressiveLoadingIndicator(
          size: size >= 40 ? ExpressiveLoadingIndicator.defaultSize : size,
          color: color,
          contained: contained,
          running: active,
        ),
      );
    }
    final ink = color ?? AppColors.ink;
    return _Appear(
      delay: delay,
      child: _InkLoop(
        period: const Duration(milliseconds: 2600),
        enabled: active,
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
                        color: ink,
                      )
                    : StampStrokes(ring: 1, stem: 1, branch: 1, color: ink),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pull to refresh, with the stamp in place of the platform's spinner.
///
/// The stamp shows still and faint while the page is pulled, whole once the
/// pull would refresh, and is drawn over and over while the refresh runs.
/// It sits on the page itself, below the top bar, with nothing behind it.
///
/// Android puts Material 3 Expressive's contained loading indicator there
/// instead, in a raised puck, on the same pull.
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
    final refreshing = status == RefreshIndicatorStatus.refresh;
    final reduced = AppMotion.reduced(context);
    final duration = reduced ? Duration.zero : AppMotion.fast;
    final material = _material(context);

    // Android: the contained indicator in its puck, as in M3 Expressive's
    // pull to refresh -- a little smaller while pulled, full size once the
    // pull would refresh, morphing while it runs. Opaque throughout: a
    // see-through disc reads as a disabled one.
    final Widget mark;
    if (!shown) {
      mark = SizedBox.square(
        dimension: material ? ExpressiveLoadingIndicator.defaultSize : 28,
      );
    } else if (material) {
      mark = AnimatedScale(
        scale: pulled ? 1 : 0.8,
        duration: duration,
        curve: AppMotion.settle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkStampIndicator(
            size: ExpressiveLoadingIndicator.defaultSize,
            delayed: false,
            active: refreshing,
            contained: true,
          ),
        ),
      );
    } else {
      mark = InkStampIndicator(delayed: false, active: refreshing);
    }

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
              opacity: !shown
                  ? 0
                  : pulled || material
                  ? 1
                  : 0.6,
              duration: duration,
              child: Center(child: mark),
            ),
          ),
        ),
      ],
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
    this.color = AppColors.ink,
  });

  final double ring;
  final double stem;
  final double branch;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    final ink = Paint()
      ..color = color
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
      old.ring != ring ||
      old.stem != stem ||
      old.branch != branch ||
      old.color != color;
}

/// Holds its child back for [delay], then fades it in.
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

/// Repeats [builder]'s phase over [period] while motion is allowed and
/// [enabled]; stands still (moving false) otherwise, and in tests.
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
