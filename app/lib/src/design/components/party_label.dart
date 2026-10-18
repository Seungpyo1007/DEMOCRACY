import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// A party name in its own colour, with an optional 여/야 mark beside it.
///
/// The name is always drawn as text; the colour fills the tag behind it and
/// never stands in for it, so a reader who cannot tell two colours apart
/// still reads two names. The text colour on the fill is picked by contrast
/// ([onColor]), so a pale party colour gets ink and a dark one gets white,
/// both at WCAG AA or better. With no colour the tag is the neutral grey
/// outline.
///
/// The side mark is a separate outlined box with the character in it (여 or
/// 야), also never colour alone, and is read out in full ([sideLabel]).
///
/// Laid out as a [Wrap], not a [Row]: callers place it both under a bounded
/// width (where a long name has to ellipsize) and in unbounded rows and
/// intrinsic-height rows, and a Wrap answers all three.
class PartyLabel extends StatelessWidget {
  const PartyLabel({
    required this.name,
    this.color,
    this.sideMark,
    this.sideLabel,
    super.key,
  });

  final String name;

  /// The party's own colour; null draws the neutral outline.
  final Color? color;

  /// `여` or `야`; null draws no mark.
  final String? sideMark;

  /// What a screen reader says for [sideMark]: `여당`, `야당`.
  final String? sideLabel;

  /// WCAG contrast ratio between two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// AA for normal-size text. The tag is 12px, so the large-text 3:1 does
  /// not apply.
  static const minContrast = 4.5;

  /// The text colour for [fill]: white or ink, whichever reads better, and if
  /// neither reaches [minContrast], pure black or white (one of the two always
  /// clears 4.5:1 against any colour).
  static Color onColor(Color fill) {
    final opaque = fill.withValues(alpha: 1);
    final white = contrast(opaque, AppColors.white);
    final ink = contrast(opaque, AppColors.ink);
    final best = white >= ink ? AppColors.white : AppColors.ink;
    if (contrast(opaque, best) >= minContrast) {
      return best;
    }
    const black = Color(0xFF000000);
    return contrast(opaque, black) >= white ? black : AppColors.white;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = BorderRadius.circular(
      surface.isGlass ? 999 : AppRadii.androidChip,
    );
    final fill = color?.withValues(alpha: 1);

    final tag = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: fill ?? AppColors.neutral500),
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: 2,
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.tag.copyWith(
            color: fill == null ? AppColors.neutral700 : onColor(fill),
          ),
        ),
      ),
    );

    final mark = sideMark;
    return Semantics(
      container: true,
      label: [name, ?sideLabel].join(', '),
      child: ExcludeSemantics(
        child: mark == null
            ? tag
            : Wrap(
                spacing: AppSpacing.x1,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  tag,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.neutral700),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      child: Text(
                        mark,
                        style: AppTextStyles.tag.copyWith(
                          color: AppColors.neutral800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
