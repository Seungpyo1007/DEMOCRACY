import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/design/components/sparkline.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The home: who holds this seat, what they have done, who is running.
///
/// Ordered incumbent-then-challengers because that is the question a resident
/// arrives with. Everything is one scroll, set as a printed page: numbered
/// sections under an ink rule, rows between hairlines, no cards. The
/// candidate rail is horizontal so no challenger gets the top of a list.
class DistrictHomeScreen extends ConsumerWidget {
  const DistrictHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(districtProfileProvider)
      ..invalidate(pledgeBoardProvider);
    await ref.read(districtProfileProvider.future);
  }

  /// Pushes the address search page and moves the resident to the district
  /// picked there.
  static Future<void> _changeDistrict(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picked = await context.push<AddressSuggestion>(
      AppRoutes.addressSearch,
    );
    if (picked != null) {
      // Read-only, not verified: the residency proof was issued for the old
      // address and does not carry over to a new one.
      ref
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: picked.district);
    }
  }

  /// Only the verified state gets a tick. `읽기 전용` is the absence of
  /// verification, and marking it with the same affirmative glyph would say
  /// the opposite of what it means.
  static Widget _verificationChip(AddressStatus status) => switch (status) {
    AddressStatus.verified => const VerifiedBadge(label: '주민 인증됨'),
    AddressStatus.pending => const StatusChip(label: '인증 대기'),
    AddressStatus.unverified => const StatusChip(label: '읽기 전용'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(addressControllerProvider);
    final profile = ref.watch(districtProfileProvider);
    final board = ref.watch(pledgeBoardProvider);

    if (address.district == null) {
      return const Scaffold(body: _NoDistrictYet());
    }

    // The district name is the page title and the switch is a toolbar
    // action: the platform's own top bar on Android, a glass button on iOS.
    // `.adaptive` gives iOS its own activity spinner for the pull.
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () => _refresh(ref),
        child: EditorialScrollView(
          title: address.district!.displayName,
          kicker: '내 지역구',
          trailing: _verificationChip(address.status),
          actions: [
            AppToolbarButton(
              icon: AppIcons.swapDistrict,
              label: '지역구 변경',
              onPressed: () => _changeDistrict(context, ref),
            ),
            AppMenuButton(
              icon: AppIcons.more,
              semanticLabel: '더보기',
              items: const [AppMenuItem(label: '튜토리얼 다시 보기')],
              onSelected: (_) => context.push('${AppRoutes.tutorial}?replay=1'),
            ),
          ],
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.x6),
              sliver: SliverList.list(
                children: [
                  RevealIn(
                    index: 1,
                    child: Padding(
                      padding: kPagePadding,
                      child: AsyncSection<DistrictProfile>(
                        value: profile,
                        onRetry: () => ref.invalidate(districtProfileProvider),
                        builder: (context, data) =>
                            _IncumbentSection(profile: data, board: board),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x8),
                  RevealIn(
                    index: 3,
                    child: AsyncSection<DistrictProfile>(
                      value: profile,
                      onRetry: () => ref.invalidate(districtProfileProvider),
                      builder: (context, data) => _CandidateSection(
                        candidates: data.candidates,
                        fallbackSource: data.source,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDistrictYet extends StatelessWidget {
  const _NoDistrictYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Text(
          '지역구를 설정하면 의원과 후보 정보를 표시합니다.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
        ),
      ),
    );
  }
}

/// One badge per publisher behind [sources], in first-seen order.
///
/// A row of figures usually comes from one publisher through several queries.
/// Printing a badge per query would repeat the same name three times; printing
/// one per publisher keeps every figure followable without the noise.
class _SourceBadges extends StatelessWidget {
  const _SourceBadges({required this.sources});

  final Iterable<SourceMetadata> sources;

  @override
  Widget build(BuildContext context) {
    final byPublisher = <String, SourceMetadata>{};
    for (final source in sources) {
      byPublisher.putIfAbsent(source.publisher, () => source);
    }

    return Wrap(
      spacing: AppSpacing.x3,
      children: [
        for (final source in byPublisher.values) SourceBadge(source: source),
      ],
    );
  }
}

/// Section 01: who holds the seat, three figures, and the record behind
/// in-page tabs.
class _IncumbentSection extends StatefulWidget {
  const _IncumbentSection({required this.profile, required this.board});

  final DistrictProfile profile;
  final AsyncValue<PledgeBoard> board;

  @override
  State<_IncumbentSection> createState() => _IncumbentSectionState();
}

class _IncumbentSectionState extends State<_IncumbentSection> {
  static const _tabs = ['공약', '법안', '출석', '표결'];

  int _tab = 0;

  Widget _pane(LegislatorRecord? record) {
    return switch (_tab) {
      0 => AsyncSection<PledgeBoard>(
        value: widget.board,
        builder: (context, data) => _PledgePane(board: data),
      ),
      _ when record == null => const _RecordMissing(),
      1 => _BillPane(bills: record.bills),
      2 => switch (record.attendance) {
        final series? => _SeriesPane(series: series, title: '월별 출석률'),
        null => const _RecordMissing(message: '출석 기록이 아직 공개되지 않았습니다.'),
      },
      _ => switch (record.votes) {
        final series? => _SeriesPane(series: series, title: '월별 표결 참여율'),
        null => const _RecordMissing(message: '표결 기록이 아직 없습니다.'),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final incumbent = widget.profile.incumbent;
    final stats = incumbent.stats.take(3).toList();
    final reduced = AppMotion.reduced(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '01', label: '현직 의원'),
        const SizedBox(height: AppSpacing.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GrayscalePortrait(
              name: incumbent.name,
              imageUrl: incumbent.portraitUrl,
              width: 76,
              height: 96,
            ),
            const SizedBox(width: AppSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incumbent.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 28,
                      letterSpacing: -0.56,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Row(
                    children: [
                      Flexible(child: PartyTag(party: incumbent.party)),
                      if (incumbent.summary.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.x2),
                        Flexible(
                          child: Text(
                            incumbent.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.ctaSmall.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.neutral600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        // No margin note on the tenure: the payload carries no election
        // years, and a note the data cannot back would be an invented fact.
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x6),
          // Three across: figure over name, scanned left to right before
          // any of them is read.
          FigureRow(
            children: [
              for (var i = 0; i < stats.length; i++)
                FigureStat(
                  value: stats[i].value.value,
                  unit: stats[i].unit,
                  label: stats[i].label,
                  delay: AppMotion.staggerFor(i + 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          _SourceBadges(sources: [for (final s in stats) s.value.source]),
        ],
        const SizedBox(height: AppSpacing.x6),
        InlineTabs(
          labels: _tabs,
          selectedIndex: _tab,
          onSelected: (index) => setState(() => _tab = index),
        ),
        // The panes differ in height, so the section eases to the new one
        // rather than jumping under the reader's thumb.
        MotionSize(
          child: AnimatedSwitcher(
            duration: reduced ? Duration.zero : AppMotion.base,
            switchInCurve: AppMotion.settle,
            switchOutCurve: AppMotion.settle,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _pane(incumbent.record),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordMissing extends StatelessWidget {
  const _RecordMissing({this.message = '의정 활동 기록이 아직 연결되지 않았습니다.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
      ),
    );
  }
}

/// A pane's last line: where it came from, and how much more there is.
class _PaneFooter extends StatelessWidget {
  const _PaneFooter({required this.source, this.trailing});

  final SourceMetadata source;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SourceBadge(source: source)),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.x2),
          trailing!,
        ],
      ],
    );
  }
}

class _PledgePane extends StatelessWidget {
  const _PledgePane({required this.board});

  final PledgeBoard board;

  /// The home is a summary; the tracker is the list.
  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    if (board.pledges.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x8),
        child: Text(
          '등록된 공약이 없습니다.',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
        ),
      );
    }

    final router = GoRouter.maybeOf(context);
    final shown = board.pledges.take(_shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          RevealIn(
            index: i,
            child: RuledRow(
              onTap: router == null
                  ? null
                  : () => router.push(AppRoutes.pledgeDetail(shown[i].id)),
              child: Row(
                children: [
                  if (shown[i].category.isNotEmpty) ...[
                    SizedBox(
                      width: 34,
                      child: Text(
                        shown[i].category,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: AppTextStyles.disclaimer.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                  ],
                  Expanded(
                    child: Text(
                      shown[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardBody.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  PledgeStatusChip(status: shown[i].status),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.x1),
        _PaneFooter(
          source: board.source,
          trailing: TextLink(
            label: '전체 ${board.total}건 →',
            onTap: router == null ? null : () => router.go(AppRoutes.tracker),
          ),
        ),
      ],
    );
  }
}

class _BillPane extends StatelessWidget {
  const _BillPane({required this.bills});

  final BillRecord bills;

  @override
  Widget build(BuildContext context) {
    final shown = bills.items.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          RevealIn(
            index: i,
            child: RuledRow(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shown[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '${shown[i].stage} · ${shown[i].stamp}',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.x1),
        // No arrow: there is no bill list to go to yet, and an arrow that
        // leads nowhere is a promise the screen cannot keep.
        _PaneFooter(
          source: bills.source,
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              widthFactor: 1,
              child: Text(
                '전체 ${bills.total}건',
                style: AppTextStyles.ctaSmall.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeriesPane extends StatelessWidget {
  const _SeriesPane({required this.series, required this.title});

  final ActivitySeries series;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
              Text(
                series.latestDisplay,
                style: AppTextStyles.figureSmall.copyWith(
                  fontSize: 24,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Sparkline(series: series, height: 88),
          const SizedBox(height: AppSpacing.x2),
          const Divider(height: 1, color: AppColors.divider),
          _PaneFooter(
            source: series.source,
            trailing: Text(
              '${series.minimum.round()}–${series.maximum.round()}${series.unit}',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 02: the challengers, side by side.
///
/// Horizontal on purpose: a vertical list would give whoever is first the
/// position a reader treats as ranked. Every card is the same width and
/// height and carries the same fields in the same order, and the sort rule
/// is printed on the section rule so the order is never mistaken for a
/// judgement.
class _CandidateSection extends StatelessWidget {
  const _CandidateSection({
    required this.candidates,
    required this.fallbackSource,
  });

  final List<Politician> candidates;

  /// Where the list itself came from, for a list whose cards carry no figure.
  final SourceMetadata fallbackSource;

  @override
  Widget build(BuildContext context) {
    final figureSources = [
      for (final candidate in candidates)
        for (final stat in candidate.stats.take(1)) stat.value.source,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: kPagePadding,
          child: SectionHeader(
            number: '02',
            label: '출마 후보 ${candidates.length}명',
            // The domain has one ordering, so the menu has one item, checked.
            // It is still a menu so the rule reads as a setting the reader
            // can inspect, not a caption (N-2).
            trailing: AppMenuButton(
              label: '정렬 ${DistrictProfile.sortLabel}',
              semanticLabel: '후보 정렬 기준 ${DistrictProfile.sortLabel}',
              items: const [
                AppMenuItem(label: DistrictProfile.sortLabel, checked: true),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        if (candidates.isEmpty)
          Padding(
            padding: kPagePadding,
            child: Text(
              '등록된 후보가 없습니다.',
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          )
        else
          // A Row under IntrinsicHeight rather than a fixed-height list, so
          // every card takes the height of the tallest -- equal whatever the
          // text scale -- without any card being clipped.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: kPagePadding,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < candidates.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.x3 + 2),
                    RevealIn(
                      index: i,
                      child: _CandidateCard(candidate: candidates[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.x3),
        Padding(
          padding: kPagePadding,
          child: _SourceBadges(
            sources: figureSources.isEmpty ? [fallbackSource] : figureSources,
          ),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  static const _width = 156.0;

  final Politician candidate;

  @override
  Widget build(BuildContext context) {
    final stat = candidate.stats.isEmpty ? null : candidate.stats.first;

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GrayscalePortrait(
            name: candidate.name,
            imageUrl: candidate.portraitUrl,
            width: _width,
            height: 124,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            candidate.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 19),
          ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            children: [
              Flexible(child: PartyTag(party: candidate.party)),
              if (candidate.summary.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.x1 + 2),
                Flexible(
                  child: Text(
                    candidate.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.x2),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  stat?.label ?? '공개된 수치 없음',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
              if (stat != null)
                Figure(
                  value: stat.value.value,
                  unit: stat.unit,
                  style: AppTextStyles.figureSmall.copyWith(
                    fontSize: 22,
                    color: AppColors.ink,
                  ),
                  unitStyle: AppTextStyles.figureUnit.copyWith(
                    fontSize: 12,
                    color: AppColors.ink,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
