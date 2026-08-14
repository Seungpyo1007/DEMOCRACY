import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/sparkline.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:democracy/src/features/onboarding/presentation/address_search_sheet.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The home: who holds this seat, what they have done, who is running.
///
/// Ordered incumbent-then-challengers because that is the question a resident
/// arrives with. Everything below the header is one scroll, and the candidate
/// rail is horizontal so no challenger gets the top of a list.
class DistrictHomeScreen extends ConsumerWidget {
  const DistrictHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(districtProfileProvider)
      ..invalidate(pledgeBoardProvider);
    await ref.read(districtProfileProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(addressControllerProvider);
    final profile = ref.watch(districtProfileProvider);
    final board = ref.watch(pledgeBoardProvider);

    if (address.district == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: _NoDistrictYet(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          slivers: [
            _DistrictHeader(address: address),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x2,
                AppSpacing.screen,
                AppSpacing.x8,
              ),
              sliver: SliverList.list(
                children: [
                  const SectionLabel('현직 의원'),
                  const SizedBox(height: AppSpacing.x3),
                  AsyncSection<DistrictProfile>(
                    value: profile,
                    onRetry: () => ref.invalidate(districtProfileProvider),
                    builder: (context, data) =>
                        _IncumbentCard(profile: data, board: board),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AsyncSection<DistrictProfile>(
                    value: profile,
                    onRetry: () => ref.invalidate(districtProfileProvider),
                    builder: (context, data) =>
                        _CandidateRail(candidates: data.candidates),
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

/// Pinned, because the district a figure belongs to is never optional context.
class _DistrictHeader extends ConsumerWidget {
  const _DistrictHeader({required this.address});

  final AddressState address;

  /// Only the verified state gets a tick. `읽기 전용` is the absence of
  /// verification, and marking it with the same affirmative glyph would say
  /// the opposite of what it means.
  Widget get _verificationChip => switch (address.status) {
    AddressStatus.verified => const VerifiedBadge(label: '주민 인증됨'),
    AddressStatus.pending => const StatusChip(label: '인증 대기'),
    AddressStatus.unverified => const StatusChip(label: '읽기 전용'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      toolbarHeight: 68,
      titleSpacing: AppSpacing.screen,
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const MicroLabel('내 지역구'),
                const SizedBox(height: 2),
                _DistrictSelector(name: address.district!.displayName),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          _verificationChip,
        ],
      ),
    );
  }
}

class _DistrictSelector extends ConsumerWidget {
  const _DistrictSelector({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: '지역구 변경',
      child: InkWell(
        onTap: () async {
          final picked = await AddressSearchSheet.show(context);
          if (picked != null) {
            // Read-only, not verified: the residency proof was issued for the
            // old address and does not carry over to a new one.
            ref
                .read(addressControllerProvider.notifier)
                .continueReadOnly(district: picked.district);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Icon(Icons.expand_more, size: 20, color: AppColors.ink),
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

/// Who holds the seat, with the record behind tabs.
class _IncumbentCard extends StatefulWidget {
  const _IncumbentCard({required this.profile, required this.board});

  final DistrictProfile profile;
  final AsyncValue<PledgeBoard> board;

  @override
  State<_IncumbentCard> createState() => _IncumbentCardState();
}

class _IncumbentCardState extends State<_IncumbentCard>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['공약', '법안', '출석', '표결'];

  late final TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incumbent = widget.profile.incumbent;
    final record = incumbent.record;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.x3 + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GrayscalePortrait(
                      name: incumbent.name,
                      imageUrl: incumbent.portraitUrl,
                      width: 64,
                      height: 80,
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            incumbent.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.x1 + 2),
                          Row(
                            children: [
                              Flexible(child: PartyTag(party: incumbent.party)),
                              if (incumbent.summary.isNotEmpty) ...[
                                const SizedBox(width: AppSpacing.x2),
                                Text(
                                  incumbent.summary,
                                  style: AppTextStyles.statLabel.copyWith(
                                    color: AppColors.neutral600,
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
                const SizedBox(height: AppSpacing.x4),
                // Three across, as the guide draws them: figure over name,
                // scanned left to right before any of them is read.
                Row(
                  children: [
                    for (final stat in incumbent.stats)
                      Expanded(
                        child: StatCell(value: stat.display, label: stat.label),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.neutral200),
          TabBar(
            controller: _controller,
            labelPadding: EdgeInsets.zero,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorColor: AppColors.signal,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.neutral600,
            labelStyle: AppTextStyles.tabLabel,
            unselectedLabelStyle: AppTextStyles.tabLabel,
            tabs: [for (final tab in _tabs) Tab(height: 38, text: tab)],
          ),
          const Divider(height: 1, color: AppColors.neutral200),

          // A fixed height because the four panes have different natural
          // heights and a TabBarView cannot size to the active one; letting it
          // resize per tab would make the card jump under the reader's thumb.
          SizedBox(
            height: 188,
            child: TabBarView(
              controller: _controller,
              children: [
                AsyncSection<PledgeBoard>(
                  value: widget.board,
                  builder: (context, data) => _PledgePane(board: data),
                ),
                if (record == null)
                  const _RecordMissing()
                else
                  _BillPane(bills: record.bills),
                if (record == null)
                  const _RecordMissing()
                else
                  _SeriesPane(series: record.attendance, title: '월별 출석률'),
                if (record == null)
                  const _RecordMissing()
                else
                  _SeriesPane(series: record.votes, title: '월별 표결 참여율'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordMissing extends StatelessWidget {
  const _RecordMissing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Text(
          '의정 활동 기록이 아직 연결되지 않았습니다.',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
        ),
      ),
    );
  }
}

class _PaneFooter extends StatelessWidget {
  const _PaneFooter({required this.source, required this.trailing});

  final SourceBadge source;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x2),
      child: Row(
        children: [
          Expanded(child: source),
          const SizedBox(width: AppSpacing.x2),
          Text(
            trailing,
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PledgePane extends StatelessWidget {
  const _PledgePane({required this.board});

  final PledgeBoard board;

  /// The card is a summary; the tracker is the list. Three keeps the pane the
  /// same height whatever the district's pledge count is.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    if (board.pledges.isEmpty) {
      return const Center(child: Text('등록된 공약이 없습니다.'));
    }

    final shown = board.pledges.take(_shown);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3 + 2,
        AppSpacing.x3,
        AppSpacing.x3 + 2,
        AppSpacing.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final pledge in shown) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    pledge.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                PledgeStatusChip(status: pledge.status),
              ],
            ),
            const SizedBox(height: AppSpacing.x2 + 2),
          ],
          const Spacer(),
          const Divider(height: 1, color: AppColors.neutral200),
          _PaneFooter(
            source: SourceBadge(source: board.source),
            trailing: '전체 ${board.total}건 →',
          ),
        ],
      ),
    );
  }
}

class _BillPane extends StatelessWidget {
  const _BillPane({required this.bills});

  final BillRecord bills;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3 + 2,
        AppSpacing.x3,
        AppSpacing.x3 + 2,
        AppSpacing.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bill in bills.items.take(3)) ...[
            Text(
              bill.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
            ),
            Text(
              '${bill.stage} · ${bill.stamp}',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
          const Spacer(),
          const Divider(height: 1, color: AppColors.neutral200),
          _PaneFooter(
            source: SourceBadge(source: bills.source),
            trailing: '전체 ${bills.total}건 →',
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x3 + 2,
        AppSpacing.x3,
        AppSpacing.x3 + 2,
        AppSpacing.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
              Text(
                series.latestDisplay,
                style: AppTextStyles.statValue.copyWith(color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          Expanded(child: Sparkline(series: series)),
          const Divider(height: 1, color: AppColors.neutral200),
          _PaneFooter(
            source: SourceBadge(source: series.source),
            trailing:
                '${series.minimum.round()}–${series.maximum.round()}${series.unit}',
          ),
        ],
      ),
    );
  }
}

/// The challengers, side by side.
///
/// Horizontal on purpose: a vertical list would give whoever is first the
/// position a reader treats as ranked. Every card is the same width and
/// carries the same fields in the same order, and the sort rule is printed
/// beside the heading so the order is never mistaken for a judgement.
class _CandidateRail extends StatelessWidget {
  const _CandidateRail({required this.candidates});

  final List<Politician> candidates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('출마 후보'),
            Text(
              '정렬 ${DistrictProfile.sortLabel}',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        if (candidates.isEmpty)
          Text(
            '등록된 후보가 없습니다.',
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: candidates.length,
              separatorBuilder: (context, _) =>
                  const SizedBox(width: AppSpacing.x3),
              itemBuilder: (context, index) =>
                  _CandidateCard(candidate: candidates[index]),
            ),
          ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final Politician candidate;

  @override
  Widget build(BuildContext context) {
    final stat = candidate.stats.isEmpty ? null : candidate.stats.first;

    return SizedBox(
      width: 150,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GrayscalePortrait(
              name: candidate.name,
              imageUrl: candidate.portraitUrl,
              width: double.infinity,
              height: 64,
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              candidate.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.x1 + 2),
            Align(
              alignment: Alignment.centerLeft,
              child: PartyTag(party: candidate.party),
            ),
            const Spacer(),
            if (stat != null)
              Text(
                '${stat.label} ${stat.display}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            if (candidate.summary.isNotEmpty)
              Text(
                candidate.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
