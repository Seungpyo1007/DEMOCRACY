import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:flutter/material.dart';

/// The map, shaded by how much has been counted and by nothing else.
///
/// This is N-1 made structural. There is no parameter here that takes a party,
/// a leader or a winner -- the only thing that reaches the fill is
/// [DistrictCount.countedShare], so the map cannot become a map of who is
/// ahead. A district's own outline is the accent, which marks where the reader
/// lives rather than who is winning there.
///
/// Google Maps needs an API key that this build does not have, so the tiles
/// are stood in for by the mockup's own grid. The shading, the selection and
/// the outline are the parts that carry the rule, and they are real.
class CountMap extends StatelessWidget {
  const CountMap({
    required this.districts,
    required this.selectedId,
    required this.homeId,
    required this.onSelected,
    this.height = 280,
    super.key,
  });

  final List<DistrictCount> districts;
  final String? selectedId;

  /// The reader's own district, outlined whatever else is selected.
  final String? homeId;

  final ValueChanged<DistrictCount> onSelected;
  final double height;

  /// Light where little is counted, dark where most is. A single-hue ramp,
  /// because two hues would read as two sides.
  static Color shadeFor(double countedFraction) {
    return Color.lerp(
      AppColors.neutral200,
      AppColors.ink,
      countedFraction.clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: AppColors.neutral200,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.x3 + 2),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final district in districts)
                    _DistrictCell(
                      district: district,
                      selected: district.districtId == selectedId,
                      home: district.districtId == homeId,
                      onTap: () => onSelected(district),
                    ),
                ],
              ),
            ),
            const Positioned(right: 10, bottom: 10, child: _CountLegend()),
          ],
        ),
      ),
    );
  }
}

class _DistrictCell extends StatelessWidget {
  const _DistrictCell({
    required this.district,
    required this.selected,
    required this.home,
    required this.onTap,
  });

  final DistrictCount district;
  final bool selected;
  final bool home;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shade = CountMap.shadeFor(district.countedFraction);

    return Semantics(
      button: true,
      selected: selected,
      // The shade is the only thing the fill encodes, so a reader who cannot
      // see it is told the number instead.
      label: '${district.districtName}, ${district.countedDisplay}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: shade,
            border: home
                ? Border.all(color: AppColors.signal, width: 3)
                : (selected
                      ? Border.all(color: AppColors.white, width: 2)
                      : null),
          ),
          child: Center(
            child: Text(
              '${district.countedShare.round()}',
              style: AppTextStyles.badge.copyWith(
                // Flip the label rather than the fill: the fill is the datum.
                color: district.countedFraction > 0.55
                    ? AppColors.white
                    : AppColors.neutral700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountLegend extends StatelessWidget {
  const _CountLegend();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.neutral300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2 + 2,
          vertical: AppSpacing.x2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '개표율 농도',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral700,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 70,
              height: 8,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.neutral200, AppColors.ink],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '0% — 100%',
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
