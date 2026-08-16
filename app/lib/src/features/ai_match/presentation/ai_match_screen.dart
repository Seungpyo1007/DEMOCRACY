import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/match_radar.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Which candidates line up with what the reader said they care about.
///
/// The screen most likely to be mistaken for an endorsement, so the disclosure
/// is pinned rather than scrolled past, and every claim in it links to the
/// pledge text it came from. The score is a fit, not a rating.
class AiMatchScreen extends ConsumerWidget {
  const AiMatchScreen({super.key});

  static const disclosure = '공약 원문 기반 참고 자료이며 공인 평가가 아닙니다.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(matchReportProvider);
    final profile = ref.watch(residentProfileProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // The disclosure and the scores are produced by one call. Deleting the
      // banner deletes the results with it, and every widget that draws a
      // score asks for the scope this installs -- so N-6 now fails loudly
      // instead of silently, the way provenance already did.
      body: DisclosedSlivers.scrollView(
        disclosure: disclosure,
        banner: const _DisclosureBanner(),
        above: [
          SliverAppBar(
            pinned: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            toolbarHeight: 72,
            titleSpacing: AppSpacing.screen,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '나에게 유리한 후보는?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.summary} 기준',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ),
        ],
        content: [
          report.when(
            loading: () =>
                const SliverToBoxAdapter(child: _AnalysingSkeleton()),
            error: (error, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: Text(
                  '분석 결과를 불러오지 못했습니다.',
                  style: AppTextStyles.cardBody.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
            ),
            data: (data) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x3,
                AppSpacing.screen,
                AppSpacing.x12,
              ),
              sliver: SliverList.list(
                children: [
                  if (data.top != null) _TopMatchCard(match: data.top!),
                  const SizedBox(height: AppSpacing.x3),
                  for (final match in data.runnersUp) ...[
                    _RunnerUpRow(match: match),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                  const SizedBox(height: AppSpacing.x6),
                  const _PremiumCta(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The N-6 banner. Pinned by [DisclosedSlivers], not by this widget: it has to
/// still be on screen at the moment a reader is looking at a score.
class _DisclosureBanner extends StatelessWidget {
  const _DisclosureBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.x2,
      ),
      child: DisclaimerBox(
        text: AiMatchScreen.disclosure,
        tone: DisclaimerTone.pinned,
        action: Semantics(
          link: true,
          child: InkWell(
            onTap: () => context.push(AppRoutes.algorithmLog),
            child: Text(
              '오픈소스 알고리즘 검증 →',
              style: AppTextStyles.badge.copyWith(
                color: AppColors.ink,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
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
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: PlatformAdaptiveProgress.circular(context),
                ),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  '분석 중 · 공약 대조',
                  style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            for (var i = 0; i < 3; i++) ...[
              Container(
                height: 12,
                width: i == 2 ? 140 : double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopMatchCard extends StatefulWidget {
  const _TopMatchCard({required this.match});

  final CandidateMatch match;

  @override
  State<_TopMatchCard> createState() => _TopMatchCardState();
}

class _TopMatchCardState extends State<_TopMatchCard> {
  final _reasonsKey = GlobalKey();

  bool _expanded = false;
  String? _focusedAxis;

  @override
  Widget build(BuildContext context) {
    // Deleting the disclosure banner takes this widget's ability to build
    // with it. The notice is not a convention any more.
    AiDisclosureScope.require(context, widget: '_TopMatchCard');

    final match = widget.match;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RankHeader(rank: '1위 매칭', score: match.scoreDisplay),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.x3 + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GrayscalePortrait(name: match.name, width: 56, height: 70),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.name,
                            style: AppTextStyles.statValue.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x1 + 2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PartyTag(party: match.party),
                          ),
                          if (match.headline.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.x1),
                            Text(
                              match.headline,
                              style: AppTextStyles.statLabel.copyWith(
                                color: AppColors.neutral600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.x4),
                MatchRadar(
                  axes: match.axes,
                  onAxisTapped: (axis) {
                    setState(() {
                      _expanded = true;
                      _focusedAxis = axis.label;
                    });
                    // Tapping an axis is a request to see why, so it opens
                    // the reasoning and scrolls to it rather than only
                    // highlighting the point.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final context = _reasonsKey.currentContext;
                      if (context != null) {
                        Scrollable.ensureVisible(
                          context,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                ),

                const SizedBox(height: AppSpacing.x4),
                for (final axis in match.axes) ...[
                  LabeledBar(
                    label: axis.label,
                    fraction: axis.fraction,
                    valueText: axis.display,
                    labelWidth: 40,
                    valueWidth: 24,
                    trackHeight: 8,
                    fillColor: axis.label == _focusedAxis
                        ? AppColors.signal
                        : AppColors.ink,
                    duration: const Duration(milliseconds: 400),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                ],
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.neutral200),
          _ReasoningSection(
            key: _reasonsKey,
            match: match,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ),
    );
  }
}

class _RankHeader extends StatelessWidget {
  const _RankHeader({required this.rank, required this.score});

  final String rank;
  final String score;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ink,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              rank,
              style: AppTextStyles.sectionLabel.copyWith(
                color: AppColors.white,
              ),
            ),
            Text(
              score,
              style: AppTextStyles.scoreDisplay.copyWith(
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The model's own explanation, arriving as it is produced.
class _ReasoningSection extends ConsumerWidget {
  const _ReasoningSection({
    required this.match,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final CandidateMatch match;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamed = expanded
        ? ref.watch(matchReasoningProvider(match.candidateId))
        : const AsyncValue<String>.loading();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3 + 2,
                vertical: AppSpacing.x3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '왜 유리한가',
                    style: AppTextStyles.ctaSmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.neutral600,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x3 + 2,
              0,
              AppSpacing.x3 + 2,
              AppSpacing.x3 + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streamed.value ?? '',
                  style: AppTextStyles.disclaimer.copyWith(
                    height: 1.6,
                    color: AppColors.neutral800,
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                // Every sentence traces back to a pledge. A model explaining
                // itself is not evidence; the original wording is.
                for (final reason in match.reasons) ...[
                  SourceBadge(source: reason.source),
                  const SizedBox(height: AppSpacing.x1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RunnerUpRow extends StatelessWidget {
  const _RunnerUpRow({required this.match});

  final CandidateMatch match;

  @override
  Widget build(BuildContext context) {
    // Deleting the disclosure banner takes this widget's ability to build
    // with it. The notice is not a convention any more.
    AiDisclosureScope.require(context, widget: '_RunnerUpRow');

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.name,
                  style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: AppSpacing.x1),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PartyTag(party: match.party),
                ),
              ],
            ),
          ),
          Text(
            match.scoreDisplay,
            style: AppTextStyles.statValue.copyWith(color: AppColors.ink),
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
      children: [
        const AppPrimaryButton(label: '상세 분석 리포트 (프리미엄)', onPressed: null),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '결제와 리포트 발행은 아직 제공하지 않습니다.',
          textAlign: TextAlign.center,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral500),
        ),
      ],
    );
  }
}
