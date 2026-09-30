import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:flutter/widgets.dart';

/// The launch motion: the 기표 도장 drawn in ink at the centre of the screen,
/// then lifted away to the app beneath.
///
/// The native splash before it is plain paper (Android's system splash has
/// an empty icon), so this is the only logo the reader sees. The ring is
/// drawn clockwise from the top, then the stem, then the short stroke, on
/// [AppMotion.writeCurve] -- the curve the app's hand underlines use -- and
/// the whole thing is over in about a second and a half. The app builds and
/// loads underneath the whole time, so the motion adds no waiting of its own.
/// With reduced motion it is skipped.
class BootSplash extends StatefulWidget {
  const BootSplash({required this.child, super.key});

  final Widget child;

  /// Stroke timings, as fractions of [total].
  static const total = Duration(milliseconds: 1540);
  static const _ring = (0.0, 620 / 1540);
  static const _stem = (560 / 1540, 860 / 1540);
  static const _branch = (820 / 1540, 1040 / 1540);

  /// Held complete, then faded out over the rest.
  static const _fadeStart = 1300 / 1540;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Made here, not lazily: with reduced motion it is never started, and a
    // first touch in dispose() would look up TickerMode on a dead element.
    _controller = AnimationController(vsync: this, duration: BootSplash.total);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = MediaQueryData.fromView(View.of(context)).disableAnimations;
    if (reduced) {
      _done = true;
      return;
    }
    // Started once the first frame is on screen, not at build: a slow start
    // (a cold engine, a busy phone) can hold frames back for a second or
    // more, and a clock already running would finish the strokes unseen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _controller.forward().orCancel.catchError((Object _) {});
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final fade = t <= BootSplash._fadeStart
                  ? 1.0
                  : 1 -
                        AppMotion.settle.transform(
                          (t - BootSplash._fadeStart) /
                              (1 - BootSplash._fadeStart),
                        );
              return IgnorePointer(
                ignoring: t > BootSplash._fadeStart,
                child: Opacity(
                  opacity: fade,
                  child: ColoredBox(
                    color: AppColors.ground,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 112,
                        child: CustomPaint(
                          key: const ValueKey('boot-stamp'),
                          painter: StampStrokes(
                            ring: _stroke(t, BootSplash._ring),
                            stem: _stroke(t, BootSplash._stem),
                            branch: _stroke(t, BootSplash._branch),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static double _stroke(double t, (double, double) span) {
    final (start, end) = span;
    if (t <= start) return 0;
    if (t >= end) return 1;
    return AppMotion.writeCurve.transform((t - start) / (end - start));
  }
}
