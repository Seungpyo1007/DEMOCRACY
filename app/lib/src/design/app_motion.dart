import 'package:flutter/widgets.dart';

/// Timing for every animation in the app.
///
/// The redesign leans on motion to carry the data: figures count up, bars
/// grow to their value, lines draw themselves, and margin notes are written
/// in. That only works if it is consistent, so nothing picks its own duration
/// or curve -- it picks a role from here.
///
/// All of it is entrance motion that runs once and settles. Nothing loops:
/// a looping animation never lets `pumpAndSettle` return, and a figure that
/// keeps moving is harder to read, not easier.
abstract final class AppMotion {
  /// Taps, toggles, a tab indicator sliding across.
  static const quick = Duration(milliseconds: 160);

  /// A section or row arriving on screen.
  static const standard = Duration(milliseconds: 320);

  /// A screen-level change: a sheet, a hero figure.
  static const emphasized = Duration(milliseconds: 560);

  /// Bars filling and numbers counting. Long enough to be followed by eye,
  /// short enough that nobody waits on it to read the value.
  static const data = Duration(milliseconds: 900);

  /// A handwritten stroke or a chart line drawing itself.
  static const draw = Duration(milliseconds: 700);

  /// Gap between siblings in a staggered entrance.
  static const stagger = Duration(milliseconds: 60);

  /// The most a stagger may add, however long the list. Past this the last
  /// row would arrive after the reader has already scrolled to it.
  static const maxStagger = Duration(milliseconds: 360);

  static const standardCurve = Curves.easeOutCubic;

  /// Material 3's emphasized decelerate: fast out of the gate, long settle.
  static const emphasizedCurve = Cubic(0.05, 0.7, 0.1, 1);

  /// For values: decelerates hard so the last digits land slowly and the
  /// final number is legible for most of the animation's length.
  static const dataCurve = Curves.easeOutQuart;

  static const drawCurve = Curves.easeInOutCubic;

  /// Whether the reader has asked the system for less motion. Every animated
  /// widget checks this and renders its end state immediately when it is set.
  static bool reduced(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// The delay for the [index]th item in a staggered list.
  static Duration staggerFor(int index) {
    final delay = stagger * index;
    return delay > maxStagger ? maxStagger : delay;
  }
}
