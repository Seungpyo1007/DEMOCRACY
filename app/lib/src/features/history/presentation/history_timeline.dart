import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/material.dart';

/// One node on a [HistoryTimeline].
class HistoryTimelineEntry {
  const HistoryTimelineEntry({
    required this.mark,
    required this.title,
    this.detail,
  });

  /// What the left column shows: `1944`, `5월`. Null when the date is not
  /// known, which is drawn as such rather than left blank.
  final String? mark;
  final String title;
  final String? detail;
}

/// A chronology set as a column of years, ring nodes on a thin rule, and text.
///
/// Distinct from `AppTimeline`, whose numbered nodes are a sequence of steps;
/// here the left column carries the date, which is the thing a reader scans.
class HistoryTimeline extends StatelessWidget {
  const HistoryTimeline({required this.entries, super.key});

  final List<HistoryTimelineEntry> entries;

  static const _markWidth = 64.0;
  static const _nodeWidth = 18.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          RevealIn(
            index: i,
            child: _Node(
              entry: entries[i],
              index: i,
              last: i == entries.length - 1,
            ),
          ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.entry, required this.index, required this.last});

  final HistoryTimelineEntry entry;
  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final mark = entry.mark;
    final markLabel = mark ?? '연도 미상';

    // A Stack rather than IntrinsicHeight: the rule is positioned against
    // the row's own height, so no intrinsic pass runs over the animated
    // children.
    return MergeSemantics(
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: HistoryTimeline._markWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: mark == null
                      // An unknown year is set smaller and grey, so it does
                      // not sit in the column with the weight of a known date.
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            markLabel,
                            style: AppTextStyles.statLabel.copyWith(
                              fontFamily: AppFonts.serif,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.neutral600,
                            ),
                          ),
                        )
                      : Text(
                          mark,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: AppTextStyles.figureSmall.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: _gap),
              const SizedBox(
                width: HistoryTimeline._nodeWidth,
                child: Padding(
                  padding: EdgeInsets.only(top: _ringTop),
                  child: Center(child: _Ring()),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.x6 - 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: AppTextStyles.cardBody.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (entry.detail != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          entry.detail!,
                          style: AppTextStyles.cardBody.copyWith(
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.neutral600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!last)
            PositionedDirectional(
              start:
                  HistoryTimeline._markWidth +
                  _gap +
                  (HistoryTimeline._nodeWidth - 1) / 2,
              width: 1,
              top: _ringTop + _Ring.size,
              bottom: 0,
              child: _GrowingRule(index: index),
            ),
        ],
      ),
    );
  }

  static const _gap = 10.0;
  static const _ringTop = 8.0;
}

class _Ring extends StatelessWidget {
  const _Ring();

  static const size = 11.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ground,
        border: Border.all(color: AppColors.ink, width: 2),
      ),
    );
  }
}

/// The rule down to the next node, drawn downward once the node has arrived.
class _GrowingRule extends StatelessWidget {
  const _GrowingRule({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return MotionIn(
      duration: AppMotion.emphasized,
      delay: AppMotion.staggerFor(index + 1),
      builder: (context, t, _) => Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: t,
          widthFactor: 1,
          child: const ColoredBox(color: AppColors.neutral300),
        ),
      ),
    );
  }
}
