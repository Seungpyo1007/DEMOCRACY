import 'package:flutter/widgets.dart';

/// Raised when AI-derived output is drawn with no disclosure above it.
///
/// A plain exception rather than an assert, for the same reason as
/// `MissingSourceException`: assertions are stripped from release builds, and
/// a machine-produced score presented as an assessment in production is
/// exactly the case that has to fail.
///
/// N-6 was the weakest of the six neutrality rules in practice. Provenance
/// throws when it is missing and a party colour has no field to live in, but
/// the disclosure was a `SliverPersistentHeader` that anyone could delete
/// while the screen went on compiling and the scores went on rendering.
class MissingDisclosureScopeException implements Exception {
  const MissingDisclosureScopeException({
    required this.widget,
    required this.reason,
  });

  final String widget;
  final String reason;

  @override
  String toString() => 'MissingDisclosureScopeException on $widget: $reason';
}

/// Installed by [DisclosedSlivers], required by anything that draws a score.
class AiDisclosureScope extends InheritedWidget {
  const AiDisclosureScope({
    required this.disclosure,
    required super.child,
    super.key,
  });

  final String disclosure;

  /// Called by every widget that renders model output.
  ///
  /// It reads through [dependOnInheritedWidgetOfExactType] rather than
  /// [getInheritedWidgetOfExactType] so the lookup is registered as a
  /// dependency -- a caller cannot satisfy this and then be rebuilt somewhere
  /// the scope is gone.
  static void require(BuildContext context, {required String widget}) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AiDisclosureScope>();
    if (scope == null) {
      throw MissingDisclosureScopeException(
        widget: widget,
        reason:
            'AI가 산출한 값은 고지 없이 표시할 수 없습니다. '
            'DisclosedSlivers.pinned로 감싸세요.',
      );
    }
  }

  @override
  bool updateShouldNotify(AiDisclosureScope oldWidget) =>
      disclosure != oldWidget.disclosure;
}

/// Builds the pinned disclosure and the content it covers, together.
///
/// This is the structural half of the fix. The scroll view is only reachable
/// through this call and it comes back inside an [AiDisclosureScope], so
/// deleting the banner deletes the screen rather than quietly removing the
/// notice. Whoever removes it has to notice.
///
/// What a type cannot express is *pinned-ness* -- that the banner is still on
/// screen at the moment a reader is looking at a score, rather than scrolled
/// away above it. That residue stays a widget test, and it is a small and
/// honest one.
abstract final class DisclosedSlivers {
  /// The measured height of the banner. Two lines of disclosure plus the
  /// verification link; the box overflowed at 66.
  static const bannerExtent = 88.0;

  /// [above] is what scrolls away over the banner -- a screen title, say.
  /// [content] is what the banner covers. Both sit inside the scope; the split
  /// exists only so the banner keeps its place in the layout.
  static Widget scrollView({
    required String disclosure,
    required Widget banner,
    required List<Widget> content,
    List<Widget> above = const [],
  }) {
    return AiDisclosureScope(
      disclosure: disclosure,
      child: CustomScrollView(
        slivers: [
          ...above,
          // Pinned, not scrolled past. N-6 is a standing disclosure: it has to
          // still be on screen at the moment a reader is looking at a score.
          SliverPersistentHeader(
            pinned: true,
            delegate: _DisclosureHeader(banner: banner),
          ),
          ...content,
        ],
      ),
    );
  }
}

class _DisclosureHeader extends SliverPersistentHeaderDelegate {
  const _DisclosureHeader({required this.banner});

  final Widget banner;

  @override
  double get minExtent => DisclosedSlivers.bannerExtent;

  @override
  double get maxExtent => DisclosedSlivers.bannerExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // The sliver expects its delegate to fill the extent exactly. Returning a
    // widget that sizes to its content leaves paintExtent short of
    // layoutExtent, which is a layout error rather than a smaller banner.
    return SizedBox(height: DisclosedSlivers.bannerExtent, child: banner);
  }

  @override
  bool shouldRebuild(_DisclosureHeader oldDelegate) =>
      banner != oldDelegate.banner;
}
