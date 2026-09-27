import 'package:flutter/widgets.dart';

/// Timing for every animation in the app.
///
/// The motion reads as a page being printed: a 2px rule is inked left to
/// right, rows are set in one after another, bars grow from their baseline,
/// lines are drawn and margin notes are written. The values here are the
/// ones on the design canvas's motion board, so nothing picks its own
/// duration or curve -- it picks a role from here.
///
/// Entrance motion runs once per screen and is over within [enterBudget].
/// Figures are never counted up: a number that ticks through values it does
/// not have dramatises a record that should only be read. The two things that
/// repeat -- a live marker and a text caret -- ask [loops] first, because a
/// looping animation never lets `pumpAndSettle` return.
abstract final class AppMotion {
  /// Presses, toggles, colour changes.
  static const fast = Duration(milliseconds: 240);

  /// A row, a heading, a dot or a dialog arriving.
  static const base = Duration(milliseconds: 520);

  /// Rules, bars and sheets -- anything that travels across the screen.
  static const slow = Duration(milliseconds: 900);

  /// A chart line drawing itself.
  static const draw = Duration(milliseconds: 1400);

  /// A margin note being written.
  static const write = Duration(milliseconds: 1300);

  /// One short shake on an error, then still.
  static const shake = Duration(milliseconds: 600);

  /// Gap between siblings in a staggered entrance.
  static const stagger = Duration(milliseconds: 72);

  /// Gap between bars, which are wider apart on the page than rows.
  static const barStagger = Duration(milliseconds: 96);

  /// How long a pane being replaced takes to go: not at all. Only arrivals
  /// move. An outgoing tab that fades as slowly as the new one comes in sits
  /// on top of it, and reads as the old content refusing to leave.
  static const leave = Duration.zero;

  /// Everything on a screen has arrived by this point.
  static const enterBudget = Duration(milliseconds: 2200);

  /// How far a row rises into place.
  static const rise = 10.0;

  /// How far a pressed button shrinks.
  static const pressScale = 0.97;

  /// Most entrances: fast out, long settle.
  static const settle = Cubic(0.2, 0.7, 0.2, 1);

  /// Rules, bars and lines -- a stroke of ink that slows as it lands.
  static const ink = Cubic(0.3, 0, 0, 1);

  /// Sheets and the tab bar docking.
  static const sheet = Cubic(0.32, 0.72, 0, 1);

  /// A pen writing: eases in and out like a hand.
  static const writeCurve = Cubic(0.45, 0.05, 0.4, 1);

  /// Whether repeating motion may run. Tests turn it off so `pumpAndSettle`
  /// returns; production leaves it on.
  static bool loopsEnabled = true;

  /// Whether the reader has asked the system for less motion. Every animated
  /// widget checks this and renders its end state immediately when it is set.
  static bool reduced(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Whether a live marker or caret may repeat.
  static bool loops(BuildContext context) => loopsEnabled && !reduced(context);

  /// The delay for the [index]th item in a staggered list, clamped so the
  /// last item still arrives within [enterBudget].
  static Duration staggerFor(int index, {bool bars = false}) {
    final delay = (bars ? barStagger : stagger) * index;
    final latest = enterBudget - slow;
    return delay > latest ? latest : delay;
  }
}
