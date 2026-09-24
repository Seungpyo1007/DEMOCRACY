import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// A block of content on the page.
///
/// In the redesign content does not sit on cards: it sits on the paper,
/// divided by rules (see `editorial.dart`). This stays as the padded block a
/// screen can still ask for, and draws no surface of its own. Floating things
/// -- a CTA bar, the results panel -- use [AppSurface] directly.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius,
    this.shadow,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Kept for callers that still pass it; a flat block has no corners.
  final double? radius;

  /// Kept for callers that still pass it; a flat block has no elevation.
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
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

    // Glass is a platter, not a wrapper: native glass buttons float on the
    // content by themselves, and a glass bar behind them would be glass on
    // glass. The bar surface is only for the Flutter stand-ins.
    if (usesNativeIosControls(context)) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            surface.navBarInset,
            0,
            surface.navBarInset,
            surface.navBarInset,
          ),
          child: child,
        ),
      );
    }

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

/// Material 3's extended FAB, for Android's primary action.
class AppExtendedFab extends StatelessWidget {
  const AppExtendedFab({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;

  /// Null draws the FAB disabled. The write gate uses this rather than
  /// hiding the button, so an unverified reader can still see what is on
  /// offer.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      backgroundColor: enabled ? null : AppColors.neutral200,
      foregroundColor: enabled ? null : AppColors.neutral600,
      elevation: enabled ? null : 0,
    );
  }
}

/// Overrides the accent a primary button fills with, for as long as it is in
/// the tree. The floating action's entrance uses it to warm the button from
/// grey to pine as it arrives.
class ActionTint extends InheritedWidget {
  const ActionTint({required this.color, required super.child, super.key});

  final Color color;

  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActionTint>()?.color;

  @override
  bool updateShouldNotify(ActionTint oldWidget) => oldWidget.color != color;
}

/// The primary action: a prominent Liquid Glass button tinted pine on iOS,
/// a Material 3 filled button on Android.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.trailingArrow = false,
    this.expand = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Kept for callers that pass it. The system buttons centre their label.
  final bool trailingArrow;
  final bool expand;
  final AppIcon? icon;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final enabled = onPressed != null;
    final accent = ActionTint.maybeOf(context) ?? AppColors.signal;

    if (!surface.isGlass) {
      final style = accent == AppColors.signal
          ? null
          : FilledButton.styleFrom(backgroundColor: accent);
      final button = icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon!.material),
              label: Text(label),
            );
      return expand ? SizedBox(width: double.infinity, child: button) : button;
    }

    if (usesNativeIosControls(context)) {
      return SizedBox(
        width: expand ? double.infinity : null,
        height: 52,
        child: CNButton(
          label: label,
          icon: icon == null ? null : CNSymbol(icon!.sfSymbol, size: 15),
          onPressed: onPressed,
          enabled: enabled,
          tint: accent,
          config: CNButtonConfig(
            style: CNButtonStyle.prominentGlass,
            minHeight: 52,
            shrinkWrap: !expand,
            labelFontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    // The stand-in for tests and older systems: a pine capsule with a glass
    // sheen, the same size as the native one.
    final radius = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled ? AppElevation.ctaWide : AppElevation.none,
      ),
      child: Material(
        color: enabled ? accent : AppColors.neutral300,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon!.material,
                      size: 18,
                      color: enabled ? AppColors.white : AppColors.neutral600,
                    ),
                    const SizedBox(width: AppSpacing.x2),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.cta.copyWith(
                        color: enabled ? AppColors.white : AppColors.neutral600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
