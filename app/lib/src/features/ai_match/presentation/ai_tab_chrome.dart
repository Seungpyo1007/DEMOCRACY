import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The two views of the AI tab, and where each one lives.
enum AiMode {
  match('후보 매칭', AppRoutes.aiMatch),
  direction('방향 분석', AppRoutes.aiDirection);

  const AiMode(this.label, this.route);

  final String label;
  final String route;
}

/// The frame every AI view shares: top bar, mode switch, disclosure.
///
/// One widget rather than two copies so the two views cannot drift apart on
/// the part that carries legal weight. The content comes in as slivers and
/// goes out inside an [AiDisclosureScope] -- every score and every
/// [AiReferenceLabel] on the page asks for that scope, so there is no way to
/// build an AI view here without the marking beside its output.
///
/// The notice itself is a system dialog shown once, on the reader's first
/// visit to the tab (and again from the ⓘ in the top bar), rather than a band
/// pinned over the results: the label beside each figure is what keeps the
/// disclosure on screen at the moment a reader looks at a score.
class AiTabScaffold extends ConsumerStatefulWidget {
  const AiTabScaffold({
    required this.mode,
    required this.title,
    required this.content,
    this.belowTitle,
    this.actions = const [],
    super.key,
  });

  final AiMode mode;

  /// The view's own question, set under the shared 'AI 분석' title.
  final String title;
  final List<Widget> content;

  /// Sits under the title, above the switch: the reader's stated profile.
  final Widget? belowTitle;

  /// Screen-level actions: [AppToolbarButton]s, which resolve to Material
  /// icon buttons in the app bar or Liquid Glass circles on iOS. The ⓘ that
  /// reopens the notice is appended to these.
  final List<Widget> actions;

  @override
  ConsumerState<AiTabScaffold> createState() => _AiTabScaffoldState();
}

class _AiTabScaffoldState extends ConsumerState<AiTabScaffold> {
  /// Whether this screen has already asked for the first-visit notice, so a
  /// rebuild while it is open does not stack a second one on top.
  bool _prompted = false;

  /// Shows the notice if the reader has never dismissed it and this screen
  /// is the one they are looking at.
  ///
  /// A tab kept alive offstage in the shell still builds, with its tickers
  /// off; so does a route covered by another. Neither is a visit, and a
  /// dialog raised from either would land over the wrong page.
  void _maybePrompt(Set<String>? seen) {
    if (_prompted || seen == null || seen.contains(TipIds.aiDisclosure)) {
      return;
    }
    if (!TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _prompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      // Read before the await: the screen may be gone by the time the
      // dialog closes, and the dismissal still has to land.
      final tips = ref.read(tipsControllerProvider.notifier);
      await showAiDisclosureDialog(context);
      // However it was closed -- 확인, 알고리즘 검증 or the barrier -- the
      // reader has seen it.
      await tips.dismiss(TipIds.aiDisclosure);
    });
  }

  @override
  Widget build(BuildContext context) {
    final district = ref.watch(districtProvider);
    // Also registers the TickerMode and route dependencies read in
    // [_maybePrompt], so arriving on the tab later rebuilds and prompts.
    _maybePrompt(ref.watch(tipsControllerProvider).value);

    // The same kicker, title and buttons in both views, so switching between
    // them leaves the top of the page standing still and only what is below
    // the switch changes. Each view names its own question under the title.
    final kicker = district?.displayName;

    return AiDisclosureScope(
      disclosure: aiDisclosure,
      child: Scaffold(
        body: EditorialScrollView(
          title: 'AI 분석',
          kicker: kicker,
          actions: [...widget.actions, const AiDisclosureAction()],
          // iOS: the 후보 매칭 | 방향 분석 switch sits in the floating tool row,
          // so the header is only a title. Android keeps it under the app bar.
          toolbarCenter: AiModeSwitch(current: widget.mode),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x2,
                AppSpacing.screen,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            if (widget.belowTitle != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.x3,
                  AppSpacing.screen,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: widget.belowTitle),
              ),
            if (!Theme.of(context).extension<AppSurfaceTokens>()!.isGlass)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.x3 + 2,
                  AppSpacing.screen,
                  AppSpacing.x3 + 2,
                ),
                sliver: SliverToBoxAdapter(
                  child: AiModeSwitch(current: widget.mode),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x3)),
            ...widget.content,
          ],
        ),
      ),
    );
  }
}

/// ⓘ: reopens the AI notice, which in turn links to the weights and inputs
/// the run used. Both AI views carry it, so it lives with the frame they
/// share.
class AiDisclosureAction extends StatelessWidget {
  const AiDisclosureAction({super.key});

  @override
  Widget build(BuildContext context) {
    return AppToolbarButton(
      icon: AppIcons.info,
      label: 'AI 분석 안내',
      onPressed: () => showAiDisclosureDialog(context),
    );
  }
}

/// 후보 매칭 | 방향 분석.
///
/// Each side is its own route, so a switch rebuilds the whole screen. The pill
/// would then jump rather than slide, which reads as a new page rather than a
/// second view of the same one -- so a new switch remembers where the last one
/// stood and slides from there on its first frame.
class AiModeSwitch extends StatefulWidget {
  const AiModeSwitch({required this.current, super.key});

  final AiMode current;

  @override
  State<AiModeSwitch> createState() => _AiModeSwitchState();
}

class _AiModeSwitchState extends State<AiModeSwitch> {
  /// Where the most recently built switch was pointing.
  static AiMode? _lastShown;

  late AiMode _shown = _lastShown ?? widget.current;

  @override
  void initState() {
    super.initState();
    _lastShown = widget.current;
    if (_shown != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _shown = widget.current);
        }
      });
    }
  }

  void _select(int index) {
    final next = AiMode.values[index];
    if (next == widget.current) {
      return;
    }
    PlatformAdaptiveHaptics.selection();
    setState(() => _shown = next);
    context.go(next.route);
  }

  @override
  Widget build(BuildContext context) {
    return AppSegmentedControl(
      segments: [for (final mode in AiMode.values) mode.label],
      selectedIndex: _shown.index,
      onSelected: _select,
    );
  }
}
