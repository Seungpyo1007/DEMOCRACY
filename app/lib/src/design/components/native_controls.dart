import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The system controls: UIKit's Liquid Glass on iOS, Material 3 on Android.
///
/// The app draws its content -- the ruled, serif page -- itself. Everything a
/// reader operates is the platform's own control instead: the tab bar, the
/// toolbar buttons, menus, search, sliders, buttons, sheets. On iOS 26 that
/// is a real `UIButton`/`UIMenu`/`UISlider` embedded as a platform view; on
/// Android it is the Material 3 widget, which *is* the native control there.
///
/// Platform views draw nothing under `flutter test`, so the iOS native path
/// is behind [AppCapabilities.nativeControls], which only the running app
/// switches on. Tests and goldens take a Flutter stand-in with the same
/// contract.

/// Whether this build can embed UIKit controls right now.
bool usesNativeIosControls(BuildContext context) {
  return Theme.of(context).extension<AppCapabilities>()?.nativeControls ??
      false;
}

bool _isGlass(BuildContext context) =>
    Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;

/// One icon, named twice: an SF Symbol for iOS and a Material icon for
/// Android. Keeping them in one value is what stops a screen from shipping a
/// Material glyph inside a UIKit control.
@immutable
class AppIcon {
  const AppIcon(this.material, this.sfSymbol);

  final IconData material;
  final String sfSymbol;
}

abstract final class AppIcons {
  static const back = AppIcon(Icons.arrow_back, 'chevron.backward');
  static const share = AppIcon(Icons.share_outlined, 'square.and.arrow.up');
  static const more = AppIcon(Icons.more_vert, 'ellipsis');
  static const info = AppIcon(Icons.info_outline, 'info.circle');
  static const sort = AppIcon(Icons.sort, 'arrow.up.arrow.down');
  static const write = AppIcon(Icons.edit_outlined, 'square.and.pencil');
  static const report = AppIcon(Icons.add, 'plus');
  static const search = AppIcon(Icons.search, 'magnifyingglass');
  static const location = AppIcon(Icons.my_location, 'location');
  static const source = AppIcon(Icons.open_in_new, 'arrow.up.right.square');
  static const person = AppIcon(Icons.person_outline, 'person.crop.circle');
  static const personFilled = AppIcon(
    Icons.account_circle,
    'person.crop.circle.fill',
  );
}

/// A toolbar action: a glass circle on iOS, a Material icon button on
/// Android.
class AppToolbarButton extends StatelessWidget {
  const AppToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final AppIcon icon;

  /// Read by screen readers and shown as the Android tooltip.
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!_isGlass(context)) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon.material),
      );
    }

    if (usesNativeIosControls(context)) {
      return Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: PaintedWhenSettled(
            child: CNButton.icon(
              icon: CNSymbol(icon.sfSymbol, size: 15),
              onPressed: onPressed,
              enabled: onPressed != null,
              tint: AppColors.ink,
            ),
          ),
        ),
      );
    }

    return _GlassCircle(
      label: label,
      onPressed: onPressed,
      child: Icon(icon.material, size: 18, color: AppColors.ink),
    );
  }
}

/// The Flutter stand-in for a glass circle, used where UIKit is unavailable.
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.white.withValues(alpha: 0.62),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.9)),
            boxShadow: AppElevation.glassSmall,
          ),
          child: child,
        ),
      ),
    );
  }
}

@immutable
class AppMenuItem {
  const AppMenuItem({required this.label, this.icon, this.checked = false});

  final String label;
  final AppIcon? icon;

  /// The current choice in a menu of mutually exclusive options.
  final bool checked;
}

/// A pull-down menu: `UIMenu` from a glass button on iOS, a Material 3
/// `MenuAnchor` on Android.
///
/// Either a text trigger ([label]) or an icon trigger ([icon]).
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    required this.items,
    required this.onSelected,
    required this.semanticLabel,
    this.label,
    this.icon,
    super.key,
  }) : assert(label != null || icon != null);

  final List<AppMenuItem> items;
  final ValueChanged<int> onSelected;
  final String semanticLabel;
  final String? label;
  final AppIcon? icon;

  @override
  Widget build(BuildContext context) {
    if (_isGlass(context)) {
      if (usesNativeIosControls(context)) {
        final entries = [
          for (final item in items)
            CNPopupMenuItem(
              label: item.label,
              checked: item.checked,
              icon: item.icon == null ? null : CNSymbol(item.icon!.sfSymbol),
            ),
        ];
        return Semantics(
          button: true,
          label: semanticLabel,
          child: icon != null
              ? SizedBox(
                  width: 44,
                  height: 44,
                  child: CNPopupMenuButton.icon(
                    buttonIcon: CNSymbol(icon!.sfSymbol, size: 15),
                    items: entries,
                    onSelected: onSelected,
                    tint: AppColors.ink,
                  ),
                )
              : CNPopupMenuButton(
                  buttonLabel: label!,
                  items: entries,
                  onSelected: onSelected,
                  tint: AppColors.ink,
                  height: 36,
                  shrinkWrap: true,
                ),
        );
      }
      return _CupertinoMenuFallback(
        items: items,
        onSelected: onSelected,
        semanticLabel: semanticLabel,
        label: label,
        icon: icon,
      );
    }

    return MenuAnchor(
      menuChildren: [
        for (var i = 0; i < items.length; i++)
          MenuItemButton(
            leadingIcon: items[i].checked
                ? const Icon(Icons.check)
                : (items[i].icon == null
                      ? const SizedBox(width: 24)
                      : Icon(items[i].icon!.material)),
            onPressed: () => onSelected(i),
            child: Text(items[i].label),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (icon != null) {
          return IconButton(
            tooltip: semanticLabel,
            onPressed: toggle,
            icon: Icon(icon!.material),
          );
        }
        return TextButton.icon(
          onPressed: toggle,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(label!),
        );
      },
    );
  }
}

/// Where UIKit is unavailable, the iOS menu becomes the Cupertino action
/// sheet the package itself falls back to.
class _CupertinoMenuFallback extends StatelessWidget {
  const _CupertinoMenuFallback({
    required this.items,
    required this.onSelected,
    required this.semanticLabel,
    this.label,
    this.icon,
  });

  final List<AppMenuItem> items;
  final ValueChanged<int> onSelected;
  final String semanticLabel;
  final String? label;
  final AppIcon? icon;

  Future<void> _open(BuildContext context) async {
    final choice = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          for (var i = 0; i < items.length; i++)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(i),
              child: Text(
                items[i].checked ? '✓ ${items[i].label}' : items[i].label,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );
    if (choice != null) {
      onSelected(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return _GlassCircle(
        label: semanticLabel,
        onPressed: () => _open(context),
        child: Icon(icon!.material, size: 18, color: AppColors.ink),
      );
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => _open(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label!,
              style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
            ),
            const SizedBox(width: 2),
            const Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 14,
              color: AppColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

/// A search field: `UISearchTextField` on iOS, Material 3 `SearchBar` on
/// Android.
///
/// With [onTap] it is a launcher rather than an input -- tapping opens a
/// search screen -- and it shows [controller]'s text, the choice already
/// made. On iOS the native field is still what is drawn; a transparent layer
/// over it takes the tap so the keyboard does not rise behind the sheet.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
    super.key,
  });

  final String placeholder;

  /// The text shown. The native iOS field keeps its own text as the reader
  /// types and reports it through [onChanged]; this pushes text into it.
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  final _native = CNSearchBarController();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_pushText);
  }

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_pushText);
      widget.controller?.addListener(_pushText);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_pushText);
    super.dispose();
  }

  /// Mirrors a programmatic change -- a picked address -- into the UIKit
  /// field. Only for the launcher: while the reader types, the native field
  /// is the source and this would echo their own keystrokes back.
  void _pushText() {
    if (widget.onTap != null) {
      _native.setText(widget.controller!.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGlass(context)) {
      if (usesNativeIosControls(context)) {
        final field = SizedBox(
          height: 44,
          child: PaintedWhenSettled(
            child: CNSearchBar(
              controller: _native,
              placeholder: widget.placeholder,
              expandable: false,
              initiallyExpanded: true,
              expandedHeight: 44,
              showCancelButton: false,
              autofocus: widget.autofocus,
              tint: AppColors.ink,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ),
        );
        if (widget.onTap == null) {
          return field;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (widget.controller?.text.isNotEmpty ?? false)) {
            _pushText();
          }
        });
        return Semantics(
          button: true,
          label: widget.placeholder,
          child: Stack(
            children: [
              field,
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                ),
              ),
            ],
          ),
        );
      }
      // The Flutter stand-in keeps the system field's own look -- grey fill,
      // system radius -- rather than a restyled one.
      return CupertinoSearchTextField(
        controller: widget.controller,
        placeholder: widget.placeholder,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
      );
    }

    return SearchBar(
      controller: widget.controller,
      hintText: widget.placeholder,
      autoFocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      leading: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        child: Icon(Icons.search),
      ),
    );
  }
}

/// A stepped slider: `UISlider` on iOS, Material 3 `Slider` on Android.
class AppSlider extends StatelessWidget {
  const AppSlider({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.valueLabel,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String semanticLabel;
  final double min;
  final double max;
  final int? divisions;

  /// Shown in the Material value indicator and read with the value.
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    if (_isGlass(context)) {
      if (usesNativeIosControls(context)) {
        return Semantics(
          slider: true,
          label: semanticLabel,
          value: valueLabel,
          child: SizedBox(
            height: 44,
            child: CNSlider(
              value: value,
              min: min,
              max: max,
              step: divisions == null ? null : (max - min) / divisions!,
              color: AppColors.signal,
              onChanged: onChanged,
            ),
          ),
        );
      }
      return Semantics(
        label: semanticLabel,
        child: CupertinoSlider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.signal,
          onChanged: onChanged,
        ),
      );
    }

    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: valueLabel,
      semanticFormatterCallback: (_) => valueLabel ?? '$value',
      onChanged: onChanged,
    );
  }
}

/// A secondary action beside a primary one: a glass button on iOS, an
/// outlined button on Android.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final AppIcon? icon;

  @override
  Widget build(BuildContext context) {
    final button = _button(context);
    // A native button already answers the press itself.
    return usesNativeIosControls(context) ? button : PressScale(child: button);
  }

  Widget _button(BuildContext context) {
    if (_isGlass(context)) {
      if (usesNativeIosControls(context)) {
        return SizedBox(
          width: expand ? double.infinity : null,
          height: 48,
          child: CNButton(
            label: label,
            icon: icon == null ? null : CNSymbol(icon!.sfSymbol, size: 14),
            onPressed: onPressed,
            enabled: onPressed != null,
            tint: AppColors.ink,
            config: CNButtonConfig(
              style: CNButtonStyle.glass,
              minHeight: 48,
              shrinkWrap: !expand,
              labelFontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      return SizedBox(
        width: expand ? double.infinity : null,
        child: CupertinoButton(
          onPressed: onPressed,
          minimumSize: const Size(44, 48),
          borderRadius: BorderRadius.circular(999),
          color: AppColors.white.withValues(alpha: 0.62),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon!.material, size: 18, color: AppColors.ink),
                const SizedBox(width: AppSpacing.x2),
              ],
              Text(
                label,
                style: AppTextStyles.ctaSmall.copyWith(
                  color: onPressed == null
                      ? AppColors.neutral600
                      : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final button = icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon!.material),
            label: Text(label),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Keeps a native control's place but does not paint it while its page is
/// sliding in, sliding out, or being covered.
///
/// A UIKit view composited into a page that Flutter is animating blanks the
/// Flutter content around it until the transition settles. Not painting the
/// native view for those few hundred milliseconds keeps the page itself on
/// time; the control appears as the page lands, the same trade the tab bar
/// makes. It stays mounted, so the UIKit view keeps its text and focus.
class PaintedWhenSettled extends StatefulWidget {
  const PaintedWhenSettled({required this.child, super.key});

  final Widget child;

  @override
  State<PaintedWhenSettled> createState() => _PaintedWhenSettledState();
}

class _PaintedWhenSettledState extends State<PaintedWhenSettled> {
  Animation<double>? _enter;
  Animation<double>? _cover;
  bool _moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _listen(route?.animation, route?.secondaryAnimation);
  }

  void _listen(Animation<double>? enter, Animation<double>? cover) {
    if (!identical(enter, _enter)) {
      _enter?.removeStatusListener(_onStatus);
      _enter = enter?..addStatusListener(_onStatus);
    }
    if (!identical(cover, _cover)) {
      _cover?.removeStatusListener(_onStatus);
      _cover = cover?..addStatusListener(_onStatus);
    }
    _onStatus(AnimationStatus.completed);
  }

  void _onStatus(AnimationStatus _) {
    final moving =
        (_enter?.status.isAnimating ?? false) ||
        (_cover?.status.isAnimating ?? false);
    if (moving != _moving && mounted) {
      setState(() => _moving = moving);
    }
  }

  @override
  void dispose() {
    _enter?.removeStatusListener(_onStatus);
    _cover?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // At opacity 0 the child is not painted at all, so no platform-view layer
    // enters the scene; layout and state are untouched.
    return Opacity(opacity: _moving ? 0 : 1, child: widget.child);
  }
}
