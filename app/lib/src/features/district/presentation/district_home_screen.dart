import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DistrictHomeScreen extends ConsumerWidget {
  const DistrictHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(addressControllerProvider);
    final districtName = address.district?.displayName ?? '지역구 미설정';

    final statusLabel = switch (address.status) {
      AddressStatus.unverified => '읽기 전용',
      AddressStatus.pending => '인증 대기',
      AddressStatus.verified => '주민 인증됨',
    };
    final statusColor = switch (address.status) {
      AddressStatus.unverified => AppColors.neutral600,
      AddressStatus.pending => AppColors.inProgress,
      AddressStatus.verified => AppColors.fulfilled,
    };

    return Scaffold(
      appBar: PlatformAdaptiveAppBar.of(context, title: '내 지역구'),
      body: address.district == null
          ? const _NoDistrictYet()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                Text(
                  districtName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.x2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      Icons.verified_user_outlined,
                      color: statusColor,
                    ),
                    label: Text(statusLabel),
                    side: BorderSide(color: statusColor),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: AppSpacing.x6),
                const _SectionLabel('현직 의원'),
                const SizedBox(height: AppSpacing.x3),
                AsyncSection(
                  value: ref.watch(districtProfileProvider),
                  onRetry: () => ref.invalidate(districtProfileProvider),
                  builder: (context, profile) =>
                      _IncumbentCard(profile: profile),
                ),
                const SizedBox(height: AppSpacing.x6),
                const _SectionLabel('공약'),
                const SizedBox(height: AppSpacing.x3),
                AsyncSection(
                  value: ref.watch(pledgeBoardProvider),
                  onRetry: () => ref.invalidate(pledgeBoardProvider),
                  builder: (context, board) => _PledgeCard(board: board),
                ),
                const SizedBox(height: AppSpacing.x6),
                AsyncSection(
                  value: ref.watch(districtProfileProvider),
                  onRetry: () => ref.invalidate(districtProfileProvider),
                  builder: (context, profile) =>
                      _CandidateSection(candidates: profile.candidates),
                ),
              ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: AppColors.neutral600),
    );
  }
}

class _IncumbentCard extends StatelessWidget {
  const _IncumbentCard({required this.profile});

  final DistrictProfile profile;

  @override
  Widget build(BuildContext context) {
    final incumbent = profile.incumbent;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GrayscalePortrait(
                name: incumbent.name,
                imageUrl: incumbent.portraitUrl,
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
                    const SizedBox(height: AppSpacing.x1),
                    Row(
                      children: [
                        Flexible(child: PartyTag(party: incumbent.party)),
                        if (incumbent.summary.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.x2),
                          Text(
                            incumbent.summary,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.neutral600),
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
          for (final stat in incumbent.stats) ...[
            _StatRow(stat: stat),
            const SizedBox(height: AppSpacing.x3),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat});

  final DistrictStat stat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stat.label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
            ),
            Text(stat.display, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.x1),
        SourceBadge(source: stat.value.source),
      ],
    );
  }
}

class _PledgeCard extends StatelessWidget {
  const _PledgeCard({required this.board});

  final PledgeBoard board;

  @override
  Widget build(BuildContext context) {
    if (board.pledges.isEmpty) {
      return AppCard(
        child: Text(
          '등록된 공약이 없습니다.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final pledge in board.pledges) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pledge.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                PledgeStatusChip(status: pledge.status),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.x3),
          SourceBadge(source: board.source),
          const SizedBox(height: AppSpacing.x1),
          Text(
            '전체 ${board.total}건',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
          ),
        ],
      ),
    );
  }
}

class _CandidateSection extends StatelessWidget {
  const _CandidateSection({required this.candidates});

  final List<Politician> candidates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionLabel('출마 후보'),
            // The ordering rule is only meaningful if the reader can see which
            // ordering is in force, so the criterion is always on screen.
            Text(
              '정렬 ${DistrictProfile.sortLabel}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        if (candidates.isEmpty)
          Text(
            '등록된 후보가 없습니다.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
          )
        else
          for (final candidate in candidates) ...[
            _CandidateCard(candidate: candidate),
            const SizedBox(height: AppSpacing.x3),
          ],
      ],
    );
  }
}

/// Every candidate gets this exact card.
///
/// One widget for all of them is what makes the equal-treatment rule hold:
/// there is no per-candidate variant to drift.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final Politician candidate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GrayscalePortrait(
            name: candidate.name,
            imageUrl: candidate.portraitUrl,
            width: 48,
            height: 60,
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.x1),
                Row(
                  children: [
                    Flexible(child: PartyTag(party: candidate.party)),
                    if (candidate.summary.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.x2),
                      Text(
                        candidate.summary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ],
                  ],
                ),
                for (final stat in candidate.stats) ...[
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '${stat.label} ${stat.display}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  SourceBadge(source: stat.value.source),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
