import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/status_donut.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Three zoom levels: the whole distribution, then by category, then one
/// pledge's judgement.
///
/// The order is the argument. A resident who only sees a headline percentage
/// cannot tell whether it was earned; the donut breaks it into counts, the
/// bars say where the work went, and the detail says who decided and on what.
class PledgeTrackerScreen extends ConsumerStatefulWidget {
  const PledgeTrackerScreen({super.key});

  @override
  ConsumerState<PledgeTrackerScreen> createState() =>
      _PledgeTrackerScreenState();
}

class _PledgeTrackerScreenState extends ConsumerState<PledgeTrackerScreen> {
  PledgeStatus? _filter;

  void _setFilter(PledgeStatus? status) {
    setState(() => _filter = status);
    PlatformAdaptiveHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(pledgeBoardProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PlatformAdaptiveAppBar.of(context, title: '공약이행률 트래커'),
      body: AsyncSection<PledgeBoard>(
        value: board,
        onRetry: () => ref.invalidate(pledgeBoardProvider),
        builder: (context, data) =>
            _Tracker(board: data, filter: _filter, onFilterChanged: _setFilter),
      ),
      bottomNavigationBar: const _ReportAction(),
    );
  }
}

class _Tracker extends StatelessWidget {
  const _Tracker({
    required this.board,
    required this.filter,
    required this.onFilterChanged,
  });

  final PledgeBoard board;
  final PledgeStatus? filter;
  final ValueChanged<PledgeStatus?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final shown = filter == null
        ? board.pledges
        : board.pledges.where((pledge) => pledge.status == filter).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x3,
        AppSpacing.screen,
        AppSpacing.x12 + AppSpacing.x8,
      ),
      children: [
        AppCard(
          child: Row(
            children: [
              StatusDonut(
                board: board,
                selected: filter,
                onStatusTapped: onFilterChanged,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: StatusLegend(
                  board: board,
                  selected: filter,
                  onStatusTapped: onFilterChanged,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        SourceBadge(source: board.source),
        const SizedBox(height: AppSpacing.x6),

        const SectionLabel('카테고리별 이행률'),
        const SizedBox(height: AppSpacing.x3),
        for (final rate in board.categories) ...[
          LabeledBar(
            label: rate.category,
            fraction: rate.share,
            valueText: rate.display,
            fillColor: AppColors.fulfilled,
            // The guide's one stated timing: fill once, 800ms, ease-out.
            duration: LabeledBar.fillDuration,
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
        const SizedBox(height: AppSpacing.x4),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SectionLabel(filter == null ? '전체 공약' : '${filter!.label} 공약'),
            Text(
              '${shown.length}건',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        for (final pledge in shown) ...[
          _PledgeRow(pledge: pledge),
          const SizedBox(height: AppSpacing.x2),
        ],
      ],
    );
  }
}

class _PledgeRow extends StatelessWidget {
  const _PledgeRow({required this.pledge});

  final Pledge pledge;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Semantics(
      button: true,
      label: '${pledge.title}, ${pledge.status.label}',
      child: InkWell(
        onTap: () => context.push(AppRoutes.pledgeDetail(pledge.id)),
        borderRadius: BorderRadius.circular(surface.cardRadius),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3 + 2,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pledge.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardBody.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      pledge.category,
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              PledgeStatusChip(status: pledge.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reporting is a write, so it is gated like every other write.
///
/// Disabled rather than hidden: an unverified resident should be able to see
/// that reporting exists and what it would take to use it.
class _ReportAction extends ConsumerWidget {
  const _ReportAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return VerifiedGate(
      onVerificationRequested: () => context.go(AppRoutes.onboarding),
      onVerified: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('제보 화면은 다음 단계에서 연결합니다.')));
      },
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppFloatingBar(
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.x2 + 2),
                Expanded(
                  child: Text(
                    '🔗 판정 기준 전체 공개',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
                AppPrimaryButton(
                  label: '이행 제보하기',
                  expand: false,
                  onPressed: onPressed,
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.x4,
            AppSpacing.x4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppExtendedFab(
                label: '이행 제보',
                icon: Icons.add,
                onPressed: onPressed,
              ),
            ],
          ),
        );
      },
    );
  }
}
