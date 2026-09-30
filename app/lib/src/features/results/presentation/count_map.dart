import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:flutter/material.dart';

/// The map, shaded by how much has been counted and by nothing else.
///
/// This is N-1 made structural. There is no parameter here that takes a party,
/// a leader or a winner -- the only thing that reaches the fill is
/// [DistrictCount.countedShare], so the map cannot become a map of who is
/// ahead. The reader's own district is marked by an inset outline in the
/// paper's colour: a cut in the tile, not a colour, so it marks where the
/// reader lives without adding a hue a reader could take for a side.
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
    this.tileHeight = 96,
    super.key,
  });

  final List<DistrictCount> districts;
  final String? selectedId;

  /// The reader's own district, outlined whatever else is selected.
  final String? homeId;

  final ValueChanged<DistrictCount> onSelected;
  final double tileHeight;

  /// Above this many tiles the grid goes to three shorter columns, so a 시도
  /// of sixty districts is a couple of screens rather than ten.
  static const denseAbove = 12;

  /// The 시도 a district is filed under: the first word of its name, '서울'
  /// in '서울 마포구 을'. The screen shows one 시도 at a time when a payload
  /// spans several.
  static String regionOf(DistrictCount district) =>
      district.districtName.split(' ').first;

  /// Light where little is counted, dark where most is. A single-hue ramp,
  /// because two hues would read as two sides.
  static Color shadeFor(double countedFraction) {
    return Color.lerp(
      AppColors.neutral200,
      AppColors.ink,
      countedFraction.clamp(0.0, 1.0),
    )!;
  }

  /// Whichever of white and ink reads better on [fill].
  ///
  /// Decided by contrast rather than by a threshold on the share, so the label
  /// flips exactly where the ramp stops supporting it -- the fill is the datum
  /// and stays put; the label is what gives way.
  static Color labelOn(Color fill) {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    return contrast(fill, AppColors.white) >= contrast(fill, AppColors.ink)
        ? AppColors.white
        : AppColors.ink;
  }

  @override
  Widget build(BuildContext context) {
    final dense = districts.length > denseAbove;
    final columns = dense ? 3 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: AppColors.neutral100,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    (constraints.maxWidth - 2 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < districts.length; i++)
                      SizedBox(
                        width: width,
                        // Grown with the reader's text size: the name and
                        // the figure are stacked in a fixed box otherwise.
                        height: MediaQuery.textScalerOf(
                          context,
                        ).scale(dense ? tileHeight * 0.75 : tileHeight),
                        child: _DistrictTile(
                          district: districts[i],
                          index: i,
                          dense: dense,
                          selected: districts[i].districtId == selectedId,
                          home: districts[i].districtId == homeId,
                          onTap: () => onSelected(districts[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        const _CountLegend(),
      ],
    );
  }
}

class _DistrictTile extends StatelessWidget {
  const _DistrictTile({
    required this.district,
    required this.index,
    required this.dense,
    required this.selected,
    required this.home,
    required this.onTap,
  });

  final DistrictCount district;
  final int index;
  final bool dense;
  final bool selected;
  final bool home;
  final VoidCallback onTap;

  /// '서울 마포구 을' is set as '마포구 을': every tile on the grid shares the
  /// city, and the tile is too narrow to repeat it. The full name is what the
  /// screen reader hears.
  String get _shortName {
    final words = district.districtName.split(' ');
    return words.length > 1 ? words.skip(1).join(' ') : district.districtName;
  }

  /// '동두천시양주시연천군 갑' split so the 갑 survives: merged districts run
  /// past a tile's width, and cut at the end, 갑 and 을 read the same.
  (String, String?) get _nameParts {
    final name = _shortName;
    final match = RegExp(r'^(.*\S)\s+([갑을병정무])$').firstMatch(name);
    return match == null ? (name, null) : (match[1]!, match[2]);
  }

  @override
  Widget build(BuildContext context) {
    final target = district.countedFraction.clamp(0.0, 1.0);

    return Semantics(
      button: true,
      selected: selected,
      // The shade is the only thing the fill encodes, so a reader who cannot
      // see it is told the number instead.
      label: '${district.districtName}, ${district.countedDisplay}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // The tiles shade in from the empty end of the ramp, one after
        // another: the map arrives the way the count does.
        child: MotionIn(
          duration: AppMotion.slow,
          delay: AppMotion.staggerFor(index),
          curve: AppMotion.ink,
          builder: (context, t, _) => TweenAnimationBuilder<double>(
            // Once in, a later count darkens the tile from where it stood.
            tween: Tween(end: target * t),
            duration: t < 1 ? Duration.zero : AppMotion.base,
            curve: AppMotion.ink,
            builder: (context, shown, _) {
              final fill = CountMap.shadeFor(shown);
              final label = CountMap.labelOn(fill);
              final nameStyle = AppTextStyles.ctaSmall.copyWith(
                color: label,
                fontSize: dense ? 12 : 13,
              );
              return DecoratedBox(
                decoration: BoxDecoration(color: fill),
                position: DecorationPosition.background,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: home
                        ? Border.all(color: AppColors.ground, width: 3)
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      dense ? AppSpacing.x2 : AppSpacing.x3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _nameParts.$1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: nameStyle,
                                    ),
                                  ),
                                  if (_nameParts.$2 != null)
                                    Text(' ${_nameParts.$2}', style: nameStyle),
                                ],
                              ),
                            ),
                            // The selection is a mark, not a tint: a tint
                            // would compete with the shade for meaning.
                            if (selected)
                              Icon(Icons.circle, size: 8, color: label),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${(shown * 100).round()}%',
                              style: AppTextStyles.figureSmall.copyWith(
                                color: label,
                                fontSize: dense ? 18 : 22,
                              ),
                            ),
                            // Its own line end, not a suffix on the name, so
                            // a long name cannot push it out of the tile.
                            if (home) ...[
                              const SizedBox(width: AppSpacing.x1),
                              Flexible(
                                child: Text(
                                  '내 지역구',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: nameStyle.copyWith(
                                    fontSize: dense ? 10 : 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
    final style = AppTextStyles.disclaimer.copyWith(
      color: AppColors.neutral600,
    );

    return ExcludeSemantics(
      child: Row(
        children: [
          Text('개표율 농도', style: style),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Container(
              height: 8,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.neutral200, AppColors.ink],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          Text('0 → 100%', style: style),
        ],
      ),
    );
  }
}
