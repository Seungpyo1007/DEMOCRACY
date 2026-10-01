import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:democracy/src/features/ai_match/presentation/on_device_notice.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
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
///
/// Between elections there are no candidates. A live build then matches the
/// sitting member's own pledges and recent bills against the reader's
/// interests, on the reader's device, and the copy says exactly that (현 의원
/// 공약과 내 관심사) instead of ranking a field of one.
class AiMatchScreen extends ConsumerWidget {
  const AiMatchScreen({super.key});

  static const disclosure = aiDisclosure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(matchReportProvider);
    final profile = ref.watch(residentProfileProvider);
    final incumbent = ref.watch(matchSubjectProvider) == MatchSubject.incumbent;

    // The disclosure and the scores are produced by one call: the scaffold
    // installs the scope, and every widget that draws a score -- and the
    // label beside it -- asks for it, so N-6 fails loudly instead of
    // silently, the way provenance already did.
    return AiTabScaffold(
      mode: AiMode.match,
      title: incumbent ? '현 의원 공약과 내 관심사' : '나에게 유리한 후보는?',
      belowTitle: _ProfileLine(summary: profile.summary, editable: incumbent),
      content: [
        report.when(
          loading: () => SliverToBoxAdapter(
            child: incumbent
                ? const _OnDeviceProgress()
                : const _AnalysingSkeleton(),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: _MatchError(error: error, incumbent: incumbent),
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
                  RevealIn(
                    index: 1,
                    child: _TopMatch(match: data.top!, subject: data.subject),
                  ),
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

/// Why there is no result, in words -- and, where the reader can do
/// something about it, the one control that does.
class _MatchError extends ConsumerWidget {
  const _MatchError({required this.error, required this.incumbent});

  final Object error;
  final bool incumbent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = AppTextStyles.cardBody.copyWith(color: AppColors.neutral700);
    void retry() => ref.invalidate(matchReportProvider);

    return switch (error) {
      OnDeviceUnavailableException(:final reason) => OnDeviceUnavailableNotice(
        reason: reason,
        onRetry: retry,
      ),
      MatchNeedsInterestsException() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '관심 분야(부동산·세금·복지·교육·청년)를 하나 이상 고르면 '
            '현 의원의 공약과 최근 대표발의 법안을 이 기기에서 대조합니다.',
            style: style,
          ),
          const SizedBox(height: AppSpacing.x3),
          AppSecondaryButton(
            label: '관심 분야 고르기',
            expand: false,
            onPressed: () => showInterestSheet(context, ref),
          ),
        ],
      ),
      OnDeviceModelException(:final readerMessage) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(readerMessage, style: style),
          const SizedBox(height: AppSpacing.x3),
          AppSecondaryButton(label: '다시 시도', expand: false, onPressed: retry),
        ],
      ),
      NotAvailableException() => Text(
        incumbent
            ? '현 의원의 공약·법안이 아직 없어 대조할 수 없습니다.'
            : '이 지역구의 AI 분석은 아직 준비 중입니다.',
        style: style,
      ),
      _ => Text('분석 결과를 불러오지 못했습니다.', style: style),
    };
  }
}

/// The chips from onboarding, again: the reader said they could change them
/// later, and this is where the answer they change is used.
///
/// Edits a copy and commits once, on 적용, so picking three chips starts one
/// run on the device rather than three.
Future<void> showInterestSheet(BuildContext context, WidgetRef ref) async {
  final picked = await PlatformAdaptiveSheet.show<Set<String>>(
    context: context,
    builder: (context) =>
        _InterestSheet(initial: ref.read(residentProfileProvider).tags),
  );
  if (picked != null) {
    ref.read(residentProfileProvider.notifier).setTags(picked);
  }
}

class _InterestSheet extends StatefulWidget {
  const _InterestSheet({required this.initial});

  final Set<String> initial;

  @override
  State<_InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends State<_InterestSheet> {
  late final Set<String> _tags = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x6,
        AppSpacing.screen,
        AppSpacing.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('관심사', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '고른 관심 분야마다 현 의원의 공약·법안과 얼마나 관련 있는지를 이 기기에서 '
            '계산합니다. 30대·자영업·1인 가구는 참고로만 쓰며, 어디에도 보내지 않습니다.',
            style: AppTextStyles.cardBody.copyWith(
              color: AppColors.neutral700,
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (final tag in ResidentProfile.availableTags)
                AppFilterChip(
                  label: tag,
                  selected: _tags.contains(tag),
                  onSelected: (_) => setState(
                    () => _tags.contains(tag)
                        ? _tags.remove(tag)
                        : _tags.add(tag),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          AppPrimaryButton(
            label: '적용',
            onPressed: () => Navigator.of(context).pop(_tags),
          ),
        ],
      ),
    );
  }
}

/// What the reader told the app about themselves, which is what the score is
/// a fit against. Shown first so the number is never read without it.
class _ProfileLine extends ConsumerWidget {
  const _ProfileLine({required this.summary, this.editable = false});

  final String summary;

  /// With a live on-device match the chips drive the axes, so they can be
  /// changed from here. The fixture's sample ran on fixed inputs; offering
  /// to change them there would change nothing.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          child: Row(
            children: [
              Expanded(
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
              if (editable)
                TextLink(
                  label: '관심사 바꾸기',
                  small: true,
                  onTap: () => showInterestSheet(context, ref),
                ),
            ],
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
    final onDevice = report.onDevice;
    final String line;
    if (onDevice != null) {
      // Where it was made is part of what it is: a model on this device, from
      // the text counted here, not something fetched.
      line =
          '공약 ${report.comparedPledges}건 · 법안 ${report.comparedBills}건 대조'
          ' · 이 기기에서 생성 · '
          '${KstInstant.fromDateTime(onDevice.generatedAt).dayLabel}';
    } else {
      final stamp = generated == null
          ? ''
          : ' · ${KstInstant.fromDateTime(generated).dayLabel} 산출';
      line = '대조한 공약 ${report.comparedPledges}건$stamp';
    }

    return Row(
      children: [
        Expanded(child: SourceLine(line)),
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
              const InkStampIndicator(),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  '후보별 공약 원문을 대조하고 있습니다',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                  ),
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

/// A run on this device, in progress: what it is reading, and each reason as
/// soon as its citation has checked out.
///
/// The model streams; what is shown of the stream is only what has passed
/// the same check as the final result, so a sentence citing a pledge that is
/// not in the input never appears even for a moment.
class _OnDeviceProgress extends ConsumerWidget {
  const _OnDeviceProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AiDisclosureScope.require(context, widget: '_OnDeviceProgress');
    final progress = ref.watch(matchProgressProvider).value;
    final verified = progress?.verified ?? const <MatchReason>[];
    final characters = progress?.characters ?? 0;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            label: '분석 중 · 이 기기에서',
            trailing: AiReferenceLabel(),
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              const InkStampIndicator(),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  characters == 0
                      ? '현 의원의 공약·법안을 관심사와 대조하고 있습니다'
                      : '근거 ${verified.length}건 확인 · 모델이 $characters자 작성',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          for (var i = 0; i < verified.length; i++)
            _NumberedReason(
              number: i + 1,
              text: verified[i].text,
              reason: verified[i],
            ),
        ],
      ),
    );
  }
}

class _TopMatch extends StatefulWidget {
  const _TopMatch({
    required this.match,
    this.subject = MatchSubject.candidates,
  });

  final CandidateMatch match;
  final MatchSubject subject;

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
    final incumbent = widget.subject == MatchSubject.incumbent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        incumbent
            ? const SectionHeader(number: '현 의원', label: '관심사 대조')
            : const SectionHeader(number: '1위', label: '매칭'),
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
          title: incumbent ? '점수 근거' : '왜 유리한가',
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
    required this.title,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final CandidateMatch match;
  final String title;
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
                        title,
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
                if (reason.axis != null)
                  Text(
                    reason.axis!,
                    style: AppTextStyles.disclaimer.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                Text(
                  text,
                  style: AppTextStyles.cardBody.copyWith(
                    color: AppColors.ink,
                    height: 1.55,
                  ),
                ),
                // What the sentence cites, by its own title, so the reader
                // knows what the link below opens before opening it.
                if (reason.cites != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SourceLine(reason.cites!),
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
