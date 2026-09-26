import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/cupertino.dart';
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
    final radius = BorderRadius.circular(
      surface.isGlass ? 999 : AppRadii.androidChip,
    );
    // Android: Material 3's own filter chip, tick and all.
    if (!surface.isGlass) {
      return FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
      );
    }

    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.quick;

    // iOS has no system chip, so this one is drawn. Selection is ink fill and
    // a tick: a state carried by colour alone is a state some readers cannot
    // see.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(!selected),
          borderRadius: radius,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.standardCurve,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3 + 2),
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.neutral400,
              ),
              borderRadius: radius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected ? '✓ $label' : label,
                  style: AppTextStyles.cardBody.copyWith(
                    fontSize: 14,
                    height: 1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppColors.ground : AppColors.ink,
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

/// The anonymous/real-name toggle.
///
/// The system switch on each platform: `UISwitch` on iOS (a Cupertino switch
/// where UIKit is unavailable), Material 3's switch with its tick on Android.
///
/// The switch only carries a boolean; what "on" means is the caller's label.
/// The review sheet labels it 익명으로 작성 and starts it on: anonymous is the
/// choice that cannot be undone by the app on the author's behalf, so it is
/// the safe rest state.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurfaceTokens>()!;

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

    if (!surface.isGlass) {
      return Semantics(
        label: semanticLabel,
        child: Switch(
          value: value,
          onChanged: onChanged,
          thumbIcon: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Icon(Icons.check)
                : null,
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      child: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.signal,
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

    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.standard;

    if (surface.isGlass) {
      // A tinted track with a white pill that slides to the selection.
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : segments.length * 110.0;
          final segment = (width - 6) / segments.length;
          return Container(
            width: width,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.ink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: duration,
                  curve: AppMotion.emphasizedCurve,
                  left: segment * selectedIndex,
                  top: 0,
                  bottom: 0,
                  width: segment,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selectedIndex,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelected(i),
                            child: Center(
                              child: Text(
                                segments[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.tabLabel.copyWith(
                                  fontSize: 13,
                                  color: i == selectedIndex
                                      ? AppColors.ink
                                      : AppColors.neutral700,
                                  fontWeight: i == selectedIndex
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    // Android: Material 3's segmented button.
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: [
          for (var i = 0; i < segments.length; i++)
            ButtonSegment(
              value: i,
              label: Text(segments[i], maxLines: 1, softWrap: false),
            ),
        ],
        selected: {selectedIndex},
        onSelectionChanged: (selection) => onSelected(selection.first),
      ),
    );
  }
}
