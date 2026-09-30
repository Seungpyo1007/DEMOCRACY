import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The building blocks of the "pine archive" layout.
///
/// The redesign drops cards for content. A screen is a printed page: sections
/// are separated by a 2px ink rule with a numbered kicker, rows by a 1px
/// hairline, and figures are set large in the serif. Glass and tonal surfaces
/// are kept for what floats -- the tab bar, a CTA bar, a sheet.

/// Horizontal page padding, the same on both platforms.
const kPagePadding = EdgeInsets.symmetric(horizontal: AppSpacing.screen);

/// The top of a tab's page: kicker, serif title, optional margin note.
///
/// iOS sets it as a large title on the paper. Android sets the same words in
/// a tonal top bar at the Material title size. Neither is a navigation bar:
/// these are root pages, and the title scrolls away with the content.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.kicker,
    this.note,
    this.trailing,
    this.onBack,
    this.backLabel,
    super.key,
  });

  final String title;
  final String? kicker;

  /// A handwritten line under the title. Descriptive only (N-5).
  final String? note;

  /// Sits at the end of the title row: a verification badge, a menu.
  final Widget? trailing;

  /// Shows a back affordance above the kicker. For pushed pages.
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final theme = Theme.of(context).textTheme;

    final back = onBack == null
        ? null
        : surface.isGlass
        ? Align(
            alignment: AlignmentDirectional.centerStart,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: onBack,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.chevron_back,
                    size: 22,
                    color: AppColors.ink,
                  ),
                  if (backLabel != null)
                    Text(
                      backLabel!,
                      style: AppTextStyles.cardBody.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                ],
              ),
            ),
          )
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: '뒤로',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
            ),
          );

    final titleStyle = surface.isGlass ? theme.displaySmall : theme.titleLarge;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?back,
        if (kicker != null)
          Text(
            kicker!,
            style: surface.isGlass
                ? AppTextStyles.sectionLabel.copyWith(
                    color: AppColors.neutral600,
                  )
                : AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                    fontWeight: FontWeight.w500,
                  ),
          ),
        const SizedBox(height: AppSpacing.x1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: titleStyle),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.x3),
              trailing!,
            ],
          ],
        ),
        if (note != null) ...[const SizedBox(height: 2), MarginNote(note!)],
      ],
    );

    if (surface.isGlass) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x4,
          AppSpacing.screen,
          0,
        ),
        child: body,
      );
    }

    return ColoredBox(
      color: AppColors.neutral100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x2,
          AppSpacing.x4,
          AppSpacing.x3 + 2,
        ),
        child: body,
      ),
    );
  }
}

/// A root or pushed page: the platform's own top bar over the editorial
/// content.
///
/// Android gets Material 3's large top app bar -- the real one, collapsing
/// into the small bar as the page scrolls, with its actions as icon buttons.
/// iOS gets what iOS 26 draws: no bar at all, the large title on the page,
/// and the actions as Liquid Glass buttons floating over the content in the
/// top corners.
///
/// [slivers] are the page below the title. [actions] are [AppToolbarButton]s
/// or icon [AppMenuButton]s; they are the same widgets on both platforms and
/// resolve their own look.
class EditorialScrollView extends StatelessWidget {
  const EditorialScrollView({
    required this.title,
    required this.slivers,
    this.kicker,
    this.note,
    this.trailing,
    this.actions = const [],
    this.onBack,
    this.controller,
    this.bottomPadding = AppSpacing.x8,
    this.floatingAction,
    this.toolbarCenter,
    super.key,
  });

  /// iOS only: a compact control in the middle of the floating tool row --
  /// the page's mode or section switch. It stays put while the page scrolls,
  /// beside the glass buttons, instead of occupying a band of its own.
  /// Android ignores it; the page draws its switch in the content, under the
  /// app bar, as Material does.
  final Widget? toolbarCenter;

  /// A compact action floating at the bottom end, above the tab bar -- the
  /// report or write button. Placed here rather than in [Scaffold]'s slot:
  /// the slot measures from the view padding, which the shell's tab bar has
  /// already consumed, and so put the action under the bar.
  final Widget? floatingAction;

  /// How far below the safe area the iOS tool row reaches, with a little
  /// air. Content scrolled to "the top" should stop here, not under the row.
  static const iosToolbarExtent = 56.0;

  /// Height a floating action takes, with its margin, at the end of a list.
  static const _floatingClearance = 56.0 + AppSpacing.x4 * 2;

  final String title;
  final List<Widget> slivers;
  final String? kicker;
  final String? note;

  /// Beside the kicker: a verification badge and the like.
  final Widget? trailing;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final ScrollController? controller;

  /// Room at the end beyond what the chrome already covers. The page runs
  /// under the tab bar (the shell extends its body), so the bar's height and
  /// the home indicator arrive as the bottom media padding and are added on
  /// top of this; a page with a floating action adds that action's height
  /// here.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final inset = MediaQuery.paddingOf(context).bottom;
    final end = SliverToBoxAdapter(
      child: SizedBox(
        height:
            inset +
            bottomPadding +
            (floatingAction == null ? 0 : _floatingClearance),
      ),
    );

    Widget withAction(Widget page) {
      if (floatingAction == null) {
        return page;
      }
      return Stack(
        children: [
          Positioned.fill(child: page),
          PositionedDirectional(
            end: AppSpacing.x4,
            bottom: inset + AppSpacing.x4,
            child: _ActionEntrance(child: floatingAction!),
          ),
        ],
      );
    }

    if (!surface.isGlass) {
      final hasLead = kicker != null || trailing != null || note != null;
      return withAction(
        CustomScrollView(
          controller: controller,
          slivers: [
            SliverAppBar.large(
              automaticallyImplyLeading: false,
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: '뒤로',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
              title: Text(title),
              actions: [
                ...actions,
                const SizedBox(width: AppSpacing.x1),
              ],
            ),
            if (hasLead)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    0,
                    AppSpacing.x4,
                    AppSpacing.x2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (kicker != null || trailing != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                kicker ?? '',
                                style: AppTextStyles.statLabel.copyWith(
                                  color: AppColors.neutral700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            ?trailing,
                          ],
                        ),
                      if (note != null) ...[
                        const SizedBox(height: AppSpacing.x1),
                        MarginNote(note!),
                      ],
                    ],
                  ),
                ),
              ),
            ...slivers,
            end,
          ],
        ),
      );
    }

    final hasToolbar =
        onBack != null || actions.isNotEmpty || toolbarCenter != null;
    final safeTop = MediaQuery.paddingOf(context).top;
    return withAction(
      Stack(
        children: [
          CustomScrollView(
            controller: controller,
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: hasToolbar ? 44 : 0),
                    child: ScreenHeader(
                      title: title,
                      kicker: kicker,
                      note: note,
                      trailing: trailing,
                    ),
                  ),
                ),
              ),
              ...slivers,
              end,
            ],
          ),
          // The scroll edge: content fades out under the status bar and the
          // tool row instead of running into them. No solid band -- that read
          // as a second bar in a different shade.
          IgnorePointer(
            child: Container(
              height: safeTop + (hasToolbar ? iosToolbarExtent : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.ground,
                    AppColors.ground.withValues(alpha: 0.92),
                    AppColors.ground.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
          if (hasToolbar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x1,
                    AppSpacing.x4,
                    0,
                  ),
                  child: Row(
                    children: [
                      if (onBack != null)
                        AppToolbarButton(
                          icon: AppIcons.back,
                          label: '뒤로',
                          onPressed: onBack,
                        ),
                      Expanded(
                        child: Center(child: toolbarCenter ?? const SizedBox()),
                      ),
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.x2),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens a section: a 2px ink rule, then `01 현직 의원` with the number set
/// apart, and an optional trailing link or control on the same line.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.number,
    this.trailing,
    super.key,
  });

  final String label;

  /// `01`, `02`... or a word like `1위`. Optional: some sections are not part
  /// of a sequence.
  final String? number;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.sectionLabel.copyWith(color: AppColors.ink);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The rule is inked left to right as the section arrives.
        const InkRule(),
        // The old border was painted inside this padding; the rule now takes
        // its own 2dp, so the gap below it is what is left.
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.x2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (number != null)
                            TextSpan(
                              text: '$number ',
                              style: style.copyWith(
                                color: AppColors.neutral600,
                              ),
                            ),
                          TextSpan(text: label),
                        ],
                      ),
                      style: style,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small grey source or date line: `7월 30일 기준 · 열린국회정보`.
class SourceLine extends StatelessWidget {
  const SourceLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.disclaimer.copyWith(color: AppColors.neutral600),
    );
  }
}

/// A trailing text link in a section header or under a list: `전체 24건 →`.
class TextLink extends StatelessWidget {
  const TextLink({
    required this.label,
    required this.onTap,
    this.small = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  /// The 11px underlined variant used in section headers.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small
        ? AppTextStyles.disclaimer.copyWith(
            color: AppColors.neutral600,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.neutral500,
          )
        : AppTextStyles.ctaSmall.copyWith(color: AppColors.ink);

    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: small ? 32 : 44),
          child: Align(
            widthFactor: 1,
            alignment: Alignment.centerRight,
            child: Text(label, style: style),
          ),
        ),
      ),
    );
  }
}

/// One line of a list: at least 54dp tall, closed by a hairline.
class RuledRow extends StatelessWidget {
  const RuledRow({
    required this.child,
    this.onTap,
    this.minHeight = 54,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final row = DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: padding,
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );

    if (onTap == null) {
      return row;
    }
    return InkWell(onTap: onTap, child: row);
  }
}

/// A handwritten margin note, written in left to right, then underlined.
///
/// Reserved for annotation: `2020년 첫 당선 · 2024년 재선`, `번복은 원문 대조
/// 가능`. It never carries data a reader needs, and it never judges.
class MarginNote extends StatelessWidget {
  const MarginNote(
    this.text, {
    this.underline = true,
    this.fontSize,
    this.delay = AppMotion.base,
    super.key,
  });

  final String text;
  final bool underline;
  final double? fontSize;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.marginNote.copyWith(
      color: AppColors.signal,
      fontSize: fontSize,
    );

    final label = Text(text, style: style);
    if (!underline) {
      return WriteIn(child: label);
    }

    return WriteIn(
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            // No width: the stretched column hands it the text's own width.
            // A LayoutBuilder here cannot answer IntrinsicWidth's question and
            // throws.
            HandUnderline(delay: delay),
          ],
        ),
      ),
    );
  }
}

/// A figure over its label, settling into place: `92%` / `출석률`.
class FigureStat extends StatelessWidget {
  const FigureStat({
    required this.value,
    required this.label,
    this.unit,
    this.fractionDigits = 0,
    this.style = AppTextStyles.statValue,
    this.delay = Duration.zero,
    super.key,
  });

  final num value;
  final String label;
  final String? unit;
  final int fractionDigits;
  final TextStyle style;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Figure(
            value: value,
            fractionDigits: fractionDigits,
            unit: unit,
            delay: delay,
            style: style.copyWith(color: AppColors.ink),
            unitStyle: AppTextStyles.figureUnit.copyWith(
              color: AppColors.ink,
              fontSize: (style.fontSize ?? 44) * 0.4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }
}

/// Figures side by side between hairlines, split by vertical rules.
class FigureRow extends StatelessWidget {
  const FigureRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.divider),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(
                            left: BorderSide(color: AppColors.divider),
                          ),
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      i == 0 ? 0 : AppSpacing.x3 + 2,
                      AppSpacing.x3 + 2,
                      AppSpacing.x2,
                      AppSpacing.x3,
                    ),
                    child: children[i],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// In-page tabs.
///
/// Each platform's own control for switching panes in place: a
/// `UISegmentedControl` on iOS (the drawn pill where UIKit is unavailable),
/// Material 3 primary tabs on Android.
class InlineTabs extends StatelessWidget {
  const InlineTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    if (surface.isGlass) {
      return AppSegmentedControl(
        segments: labels,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    return _MaterialTabs(
      labels: labels,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
    );
  }
}

/// Material's [TabBar] wants a controller; the caller owns the index, so this
/// keeps one in step with it.
class _MaterialTabs extends StatefulWidget {
  const _MaterialTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_MaterialTabs> createState() => _MaterialTabsState();
}

class _MaterialTabsState extends State<_MaterialTabs>
    with SingleTickerProviderStateMixin {
  late TabController _controller = _build();

  TabController _build() => TabController(
    length: widget.labels.length,
    initialIndex: widget.selectedIndex,
    vsync: this,
  );

  @override
  void didUpdateWidget(_MaterialTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _controller.dispose();
      _controller = _build();
    } else if (_controller.index != widget.selectedIndex) {
      _controller.animateTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: _controller,
      onTap: widget.onSelected,
      tabs: [for (final label in widget.labels) Tab(text: label)],
    );
  }
}

/// Brings a floating action in each time its page comes to the front: it
/// rises and grows into place while its fill warms from grey to the accent.
///
/// "Comes to the front" includes switching back to the tab: the shell keeps
/// every branch alive, so the page is not rebuilt, only re-enabled -- which
/// [TickerMode] reports.
class _ActionEntrance extends StatefulWidget {
  const _ActionEntrance({required this.child});

  final Widget child;

  @override
  State<_ActionEntrance> createState() => _ActionEntranceState();
}

class _ActionEntranceState extends State<_ActionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  bool? _wasActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && _wasActive != true) {
      if (AppMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
    _wasActive = active;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: _controller, curve: AppMotion.sheet);
    return AnimatedBuilder(
      animation: eased,
      child: widget.child,
      builder: (context, child) {
        final t = eased.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Transform.scale(
              scale: 0.86 + 0.14 * t,
              alignment: Alignment.bottomRight,
              child: ActionTint(
                // Settles on the exact accent so the button is not left one
                // rounding step off the brand colour.
                color: t >= 1
                    ? AppColors.signal
                    : Color.lerp(AppColors.neutral500, AppColors.signal, t)!,
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}
