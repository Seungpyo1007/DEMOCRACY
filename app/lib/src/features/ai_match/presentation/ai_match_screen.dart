import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Which candidates line up with what the reader said they care about.
///
/// The screen most likely to be mistaken for an endorsement, so every score on
/// it carries an `AI 참고 자료` label that opens the notice, and every claim in
/// it links to the pledge text it came from. The score is a fit, not a rating.
class AiMatchScreen extends ConsumerWidget {
  const AiMatchScreen({super.key});

  static const disclosure = aiDisclosure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(matchReportProvider);
    final profile = ref.watch(residentProfileProvider);

    // The disclosure and the scores are produced by one call: the scaffold
    // installs the scope, and every widget that draws a score -- and the
    // label beside it -- asks for it, so N-6 fails loudly instead of
    // silently, the way provenance already did.
    return AiTabScaffold(
      mode: AiMode.match,
      title: '나에게 유리한 후보는?',
      belowTitle: _ProfileLine(summary: profile.summary),
      content: [
        report.when(
          loading: () => const SliverToBoxAdapter(child: _AnalysingSkeleton()),
          error: (error, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: Text(
                error is NotAvailableException
                    ? '이 지역구의 AI 분석은 아직 준비 중입니다.'
                    : '분석 결과를 불러오지 못했습니다.',
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ),
          data: (data) => SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.x3,
              AppSpacing.screen,
              AppSpacing.x12 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                RevealIn(child: _MetaLine(report: data)),
                const SizedBox(height: AppSpacing.x6),
                if (data.top != null)
                  RevealIn(index: 1, child: _TopMatch(match: data.top!)),
                if (data.runnersUp.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x3),
                  RevealIn(
                    index: 2,
                    child: _RunnersUp(matches: data.runnersUp),
                  ),
                ],
                const SizedBox(height: AppSpacing.x6),
                const RevealIn(index: 3, child: _PremiumCta()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the reader told the app about themselves, which is what the score is
/// a fit against. Shown first so the number is never read without it.
class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.divider),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$summary 기준',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.cardBody.copyWith(
              fontSize: 14,
              color: AppColors.neutral700,
            ),
          ),
        ),
      ),
    );
  }
}

/// How much text the result rests on, when it was produced, and the way to
/// check the arithmetic.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    final generated = report.generatedAt;
    final stamp = generated == null
        ? ''
        : ' · ${KstInstant.fromDateTime(generated).dayLabel} 산출';

    return Row(
      children: [
        Expanded(child: SourceLine('대조한 공약 ${report.comparedPledges}건$stamp')),
        TextLink(
          label: '가중치와 입력값',
          small: true,
          onTap: () => context.push(AppRoutes.algorithmLog),
        ),
      ],
    );
  }
}

/// What a run in progress looks like.
///
/// A count of what is being compared rather than a spinner: the wait is the
/// one moment the reader is told how much text the number rests on.
class _AnalysingSkeleton extends StatelessWidget {
  const _AnalysingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(label: '분석 중 · 공약 대조'),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: PlatformAdaptiveProgress.circular(context),
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                '후보별 공약 원문을 대조하고 있습니다',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 10,
              width: i == 2 ? 140 : double.infinity,
              color: AppColors.neutral100,
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
        ],
      ),
    );
  }
}

class _TopMatch extends StatefulWidget {
  const _TopMatch({required this.match});

  final CandidateMatch match;

  @override
  State<_TopMatch> createState() => _TopMatchState();
}

class _TopMatchState extends State<_TopMatch> {
  final _reasonsKey = GlobalKey();

  bool _expanded = false;
  String? _focusedAxis;

  void _focus(MatchAxis axis) {
    setState(() {
      _expanded = true;
      _focusedAxis = axis.label;
    });
    // Tapping an axis is a request to see why, so it opens the reasoning and
    // scrolls to it rather than only highlighting the bar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _reasonsKey.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.base,
          curve: AppMotion.settle,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Deleting the disclosure scope takes this widget's ability to build
    // with it. The notice is not a convention any more.
    AiDisclosureScope.require(context, widget: '_TopMatch');

    final match = widget.match;
    final name = Theme.of(context).textTheme.headlineMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '1위', label: '매칭'),
        const SizedBox(height: AppSpacing.x3 + 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GrayscalePortrait(name: match.name, width: 64, height: 80),
            const SizedBox(width: AppSpacing.x3 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.name, style: name?.copyWith(height: 1.1)),
                  const SizedBox(height: AppSpacing.x2),
                  PartyTag(party: match.party),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Figure(
                  value: match.score.round(),
                  unit: '점',
                  style: AppTextStyles.scoreDisplay.copyWith(
                    color: AppColors.ink,
                    height: 0.95,
                  ),
                  unitStyle: AppTextStyles.figureUnit.copyWith(
                    color: AppColors.ink,
                  ),
                ),
                // The marking travels with the figure, not with the page.
                const AiReferenceLabel(),
              ],
            ),
          ],
        ),
        if (match.headline.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x3 + 2),
          Text(
            match.headline,
            style: AppTextStyles.cardBody.copyWith(
              color: AppColors.neutral700,
              height: 1.55,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.x4),
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.x2),
        for (var i = 0; i < match.axes.length; i++)
          _AxisBar(
            axis: match.axes[i],
            index: i,
            focused: match.axes[i].label == _focusedAxis,
            onTap: () => _focus(match.axes[i]),
          ),
        const SizedBox(height: AppSpacing.x3),
        _Reasoning(
          key: _reasonsKey,
          match: match,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
        ),
      ],
    );
  }
}

/// One axis of the fit, as a bar. Tappable: it opens the reasoning behind it.
class _AxisBar extends StatelessWidget {
  const _AxisBar({
    required this.axis,
    required this.index,
    required this.focused,
    required this.onTap,
  });

  final MatchAxis axis;
  final int index;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AiDisclosureScope.require(context, widget: '_AxisBar');

    return Semantics(
      button: true,
      label: '${axis.label} ${axis.display}점, 근거 보기',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: LabeledBar(
              label: axis.label,
              fraction: axis.fraction,
              valueText: axis.display,
              labelWidth: 52,
              valueWidth: 36,
              // The one piece of colour on the screen, and only when the
              // reader asked for it: which bar the reasoning below is about.
              fillColor: focused ? AppColors.signal : AppColors.ink,
              delay: AppMotion.staggerFor(index + 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The model's own explanation, arriving as it is produced, one numbered
/// reason at a time -- each followed by the pledge it came from.
class _Reasoning extends ConsumerWidget {
  const _Reasoning({
    required this.match,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final CandidateMatch match;
  final bool expanded;
  final VoidCallback onToggle;

  /// Splits the streamed prefix back into the reasons it was joined from, so
  /// the list fills in order instead of printing one run-on paragraph.
  List<String> _visibleParts(String streamed) {
    final parts = <String>[];
    var start = 0;
    for (final reason in match.reasons) {
      if (streamed.length <= start) {
        break;
      }
      final end = start + reason.text.length;
      parts.add(streamed.substring(start, end.clamp(start, streamed.length)));
      // The fake joins reasons with a single space.
      start = end + 1;
    }
    return parts;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamed = expanded
        ? ref.watch(matchReasoningProvider(match.candidateId))
        : const AsyncValue<String>.loading();
    final parts = _visibleParts(streamed.value ?? '');
    final reduced = AppMotion.reduced(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '왜 유리한가',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: reduced ? Duration.zero : AppMotion.base,
                      curve: AppMotion.settle,
                      child: const Icon(
                        Icons.expand_more,
                        size: 22,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          MotionSize(
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.x2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < parts.length; i++)
                          _NumberedReason(
                            number: i + 1,
                            text: parts[i],
                            reason: match.reasons[i],
                          ),
                        if (match.reasons.isNotEmpty)
                          TextLink(
                            label: '원문 대조 보기 ↗',
                            onTap: () => launchUrl(
                              match.reasons.first.source.sourceUrl,
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NumberedReason extends StatelessWidget {
  const _NumberedReason({
    required this.number,
    required this.text,
    required this.reason,
  });

  final int number;
  final String text;
  final MatchReason reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '$number',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: AppTextStyles.cardBody.copyWith(
                    color: AppColors.ink,
                    height: 1.55,
                  ),
                ),
                // Every sentence traces back to a pledge. A model explaining
                // itself is not evidence; the original wording is.
                SourceBadge(source: reason.source),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 2위 and below, as ruled rows.
///
/// Only the leader gets the bars; the others are a line each. A second full
/// block would read as a comparison between candidates rather than between
/// each candidate and the reader.
class _RunnersUp extends StatelessWidget {
  const _RunnersUp({required this.matches});

  final List<CandidateMatch> matches;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < matches.length; i++)
            _RunnerUpRow(rank: i + 2, match: matches[i]),
        ],
      ),
    );
  }
}

class _RunnerUpRow extends StatelessWidget {
  const _RunnerUpRow({required this.rank, required this.match});

  final int rank;
  final CandidateMatch match;

  @override
  Widget build(BuildContext context) {
    // Deleting the disclosure scope takes this widget's ability to build
    // with it. The notice is not a convention any more.
    AiDisclosureScope.require(context, widget: '_RunnerUpRow');

    return RuledRow(
      minHeight: 72,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 + 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank위',
              style: AppTextStyles.badge.copyWith(color: AppColors.neutral600),
            ),
          ),
          const SizedBox(width: AppSpacing.x2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      match.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    PartyTag(party: match.party),
                  ],
                ),
                if (match.headline.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    match.headline,
                    style: AppTextStyles.statLabel.copyWith(
                      fontSize: 13,
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x2 + 2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Figure(
                value: match.score.round(),
                unit: '점',
                delay: AppMotion.staggerFor(rank),
                style: AppTextStyles.figureSmall.copyWith(
                  fontSize: 30,
                  color: AppColors.ink,
                ),
                unitStyle: AppTextStyles.figureUnit.copyWith(
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              const AiReferenceLabel(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Named and visible, but inert.
///
/// Payments are outside this build, and a button that takes money without a
/// contract behind it would be the one piece of the screen making a promise
/// the app cannot keep.
class _PremiumCta extends StatelessWidget {
  const _PremiumCta();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPrimaryButton(label: '상세 분석 리포트 (프리미엄)', onPressed: null),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '결제와 리포트 발행은 아직 제공하지 않습니다.',
          textAlign: TextAlign.center,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }
}
