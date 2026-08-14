import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The surface every block of content sits on.
///
/// The two platforms build a card out of different materials, not just
/// different corner radii: iOS is a translucent tint with the page blurred
/// behind it and a white highlight for an edge, Android is an opaque fill with
/// a hairline border and no shadow at all. Callers should not have to know
/// which they are on, so this is the only place that does.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.radius,
    this.shadow,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides the platform card radius. The guide uses a family of glass
  /// radii by surface size, so a small row inside a card can ask for a
  /// tighter one.
  final double? radius;

  /// Overrides the platform shadow, for the surfaces the guide lifts further
  /// off the page than a plain card.
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final borderRadius = BorderRadius.circular(radius ?? surface.cardRadius);

    return AppSurface(
      borderRadius: borderRadius,
      fill: surface.cardFill,
      border: surface.cardBorder,
      shadow: shadow ?? surface.cardShadow,
      blurSigma: surface.blurSigma,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The card's shape without its padding, for callers that need to draw to the
/// edge -- a card with a coloured header, or a bar that holds its own layout.
class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    required this.borderRadius,
    required this.fill,
    required this.border,
    required this.shadow,
    required this.blurSigma,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color fill;
  final Color border;
  final List<BoxShadow> shadow;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    // Glass is a material, not a tint over a blur. `liquid_glass_widgets`
    // renders the refraction, the specular edge and the shadow together, and
    // it drops to an opaque surface on its own when the system asks for
    // Reduce Transparency -- which a hand-rolled BackdropFilter would not.
    if (blurSigma > 0) {
      return GlassCard(
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius.topLeft.x),
        child: child,
      );
    }

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: borderRadius,
      ),
      child: child,
    );

    if (shadow.isEmpty) {
      return surface;
    }

    // Outside the clip: a shadow drawn inside its own rounded rectangle is
    // clipped away by it.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
      child: surface,
    );
  }
}

/// The bar that floats over the page carrying a screen's primary action.
///
/// iOS only. Android puts the same action in an extended FAB, which is a
/// different shape in a different corner -- see [AppExtendedFab].
class AppFloatingBar extends StatelessWidget {
  const AppFloatingBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          surface.navBarInset,
          0,
          surface.navBarInset,
          surface.navBarInset,
        ),
        child: AppSurface(
          borderRadius: BorderRadius.circular(AppRadii.iosTabBar),
          fill: surface.barFill,
          border: surface.barBorder,
          shadow: surface.barShadow,
          blurSigma: surface.blurSigma,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Material's extended FAB, in the accent, at the guide's radius.
class AppExtendedFab extends StatelessWidget {
  const AppExtendedFab({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;

  /// Null disables the action. The write gate uses this rather than hiding
  /// the button, so an unverified reader can still see what is on offer.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.androidFab),
        boxShadow: enabled ? AppElevation.androidFab : AppElevation.none,
      ),
      child: Material(
        color: enabled ? AppColors.signal : AppColors.neutral300,
        borderRadius: BorderRadius.circular(AppRadii.androidFab),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.androidFab),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: AppSpacing.x3 + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: enabled ? AppColors.white : AppColors.neutral600,
                ),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  label,
                  style: AppTextStyles.ctaSmall.copyWith(
                    color: enabled ? AppColors.white : AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The accent capsule that carries a primary action.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.trailingArrow = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// iOS pushes the label left and sets an arrow on the right; Android
  /// centres the label with nothing beside it.
  final bool trailingArrow;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(
      surface.isGlass ? AppRadii.iosButtonWide : AppRadii.androidButton,
    );

    final label_ = Text(
      label,
      textAlign: trailingArrow ? TextAlign.start : TextAlign.center,
      style: AppTextStyles.cta.copyWith(
        color: enabled ? AppColors.white : AppColors.neutral600,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled && surface.isGlass
            ? AppElevation.ctaWide
            : AppElevation.none,
      ),
      child: Material(
        color: enabled ? AppColors.signal : AppColors.neutral300,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: AppSpacing.x3 + 3,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (trailingArrow) ...[
                  Expanded(child: label_),
                  Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: enabled ? AppColors.white : AppColors.neutral600,
                  ),
                ] else if (expand)
                  Expanded(child: label_)
                else
                  label_,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
