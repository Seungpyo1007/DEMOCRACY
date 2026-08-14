import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// A selectable chip, for the onboarding profile and interest tags.
///
/// Android marks selection with a leading tick as well as a fill, which is the
/// same reasoning the status chips follow: a state carried by colour alone is
/// a state some readers cannot see.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = BorderRadius.circular(surface.chipRadius);
    final showTick = selected && !surface.isGlass;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? surface.selectedChipFill : surface.cardFill,
        borderRadius: radius,
        child: InkWell(
          onTap: () => onSelected(!selected),
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? surface.selectedChipFill
                    : (surface.isGlass
                          ? surface.cardBorder
                          : AppColors.neutral400),
              ),
              borderRadius: radius,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.x3 + (surface.isGlass ? 2 : 0),
                vertical: selected ? 7 : 6,
              ),
              child: Text(
                showTick ? '✓ $label' : label,
                style: AppTextStyles.cardBody.copyWith(
                  height: 1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? surface.selectedChipForeground
                      : AppColors.neutral700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The anonymous/real-name toggle.
///
/// Drawn to the guide's dimensions rather than using [Switch], because the
/// mockup's control is a 16dp-tall ink track with a square-ish radius, and
/// Material's switch is neither.
///
/// Off means anonymous, and off is the default. The two mockups disagree about
/// which way the knob sits; anonymous is the choice that cannot be undone by
/// the app on the author's behalf, so it is the safe rest state.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  static const _knob = 12.0;
  static const _inset = 2.0;
  static const _height = 16.0;

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurfaceTokens>()!;
    final width = surface.isGlass ? 28.0 : 30.0;

    // On a real iOS process the system switch is the right control: it carries
    // the platform's own Liquid Glass treatment, its animation curve and its
    // accessibility behaviour, none of which are worth re-deriving.
    if (theme.extension<AppCapabilities>()?.nativeControls ?? false) {
      return Semantics(
        toggled: value,
        label: semanticLabel,
        child: SizedBox(
          width: 52,
          height: 32,
          child: CNSwitch(value: value, onChanged: onChanged, height: 32),
        ),
      );
    }

    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: width,
          height: _height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: value ? AppColors.ink : AppColors.neutral400,
              borderRadius: BorderRadius.circular(AppSpacing.x2),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive options.
///
/// iOS draws them as separate capsule chips; Android as one joined control
/// with hairline dividers. Same contract either way.
class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurfaceTokens>()!;

    if (theme.extension<AppCapabilities>()?.nativeControls ?? false) {
      return SizedBox(
        height: 32,
        child: CNSegmentedControl(
          labels: segments,
          selectedIndex: selectedIndex,
          onValueChanged: onSelected,
          shrinkWrap: true,
        ),
      );
    }

    if (surface.isGlass) {
      return Wrap(
        spacing: AppSpacing.x2,
        children: [
          for (var i = 0; i < segments.length; i++)
            AppFilterChip(
              label: segments[i],
              selected: i == selectedIndex,
              onSelected: (_) => onSelected(i),
            ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral400),
        borderRadius: BorderRadius.circular(AppRadii.androidButton - 4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.androidButton - 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: i == selectedIndex
                      ? AppColors.neutral200
                      : Colors.transparent,
                  border: i == 0
                      ? null
                      : const Border(
                          left: BorderSide(color: AppColors.neutral400),
                        ),
                ),
                child: Semantics(
                  button: true,
                  selected: i == selectedIndex,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x3 + 2,
                        vertical: 7,
                      ),
                      child: Text(
                        i == selectedIndex ? '✓ ${segments[i]}' : segments[i],
                        style: AppTextStyles.tabLabel.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
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
