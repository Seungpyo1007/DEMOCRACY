import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The four-way split of a district's pledges.
///
/// Tapping a segment filters the list rather than drilling into it: the
/// question this chart answers is "how many of each", and the follow-up is
/// always "which ones".
class StatusDonut extends StatelessWidget {
  const StatusDonut({
    required this.board,
    required this.onStatusTapped,
    this.selected,
    this.size = 110,
    super.key,
  });

  static const _hole = 72.0;

  final PledgeBoard board;
  final ValueChanged<PledgeStatus?> onStatusTapped;
  final PledgeStatus? selected;
  final double size;

  static Color colorOf(PledgeStatus status) => switch (status) {
    PledgeStatus.fulfilled => AppColors.fulfilled,
    PledgeStatus.inProgress => AppColors.inProgress,
    PledgeStatus.unfulfilled => AppColors.unfulfilled,
    PledgeStatus.reversed => AppColors.reversed,
  };

  @override
  Widget build(BuildContext context) {
    final present = PledgeStatus.values
        .where((status) => board.countOf(status) > 0)
        .toList(growable: false);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Semantics(
            label: [
              '종합 이행률 ${board.fulfilmentDisplay}',
              for (final status in present)
                '${status.label} ${board.countOf(status)}건',
            ].join(', '),
            excludeSemantics: true,
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 1,
                centerSpaceRadius: _hole / 2,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) {
                      return;
                    }
                    final index = response?.touchedSection?.touchedSectionIndex;
                    if (index == null || index < 0 || index >= present.length) {
                      return;
                    }
                    final status = present[index];
                    onStatusTapped(status == selected ? null : status);
                  },
                ),
                sections: [
                  for (final status in present)
                    PieChartSectionData(
                      value: board.countOf(status).toDouble(),
                      color: colorOf(status),
                      // The selected slice grows. Colour alone would be a
                      // second meaning for a hue that already carries one.
                      radius: status == selected
                          ? (size - _hole) / 2 + 5
                          : (size - _hole) / 2,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                board.fulfilmentDisplay,
                style: AppTextStyles.scoreDisplay.copyWith(
                  color: AppColors.ink,
                ),
              ),
              Text(
                '종합 이행률',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The donut's key, and the filter control that goes with it.
class StatusLegend extends StatelessWidget {
  const StatusLegend({
    required this.board,
    required this.onStatusTapped,
    this.selected,
    super.key,
  });

  final PledgeBoard board;
  final ValueChanged<PledgeStatus?> onStatusTapped;
  final PledgeStatus? selected;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in PledgeStatus.values)
          if (board.countOf(status) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Semantics(
                button: true,
                selected: status == selected,
                child: InkWell(
                  onTap: () =>
                      onStatusTapped(status == selected ? null : status),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: StatusDonut.colorOf(status),
                            // Square on iOS, round on Android, as the guide
                            // draws the swatches.
                            shape: surface.isGlass
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x2),
                      // Label over figure, as the guide sets it. One line does
                      // not fit beside the donut at 390dp, and truncating the
                      // status name would leave the swatch as the only thing
                      // naming the colour.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              // Glyph and word, not just the swatch: the
                              // legend is the one place the colours are named.
                              status.display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.tabLabel.copyWith(
                                fontWeight: status == selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: status == selected
                                    ? AppColors.ink
                                    : AppColors.neutral700,
                              ),
                            ),
                            Text(
                              '${board.countOf(status)}건 · '
                              '${(board.shareOf(status) * 100).round()}%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.statLabel.copyWith(
                                color: AppColors.neutral500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
