import 'dart:math' as math;

import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/on_device/stance_run.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:democracy/src/features/ai_match/presentation/on_device_notice.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Direction analysis: where the candidates' pledges sit, how the incumbent's
/// bills split across fields, which local issues are rising.
///
/// Two kinds of output share this page. The stance plot and the issue flow
/// are model output -- the model read wording and placed or classified it --
/// and carry the same disclosure as the match: an `AI 참고 자료` label where
/// each opens, and a scope every figure in them requires. The bill trend is
/// not: it is a count of the incumbent's bills by the committee each was
/// referred to, so it carries its basis instead of the AI label, and calling
/// it AI would misdescribe it.
///
/// Each block renders on its own. One the payload leaves out shows 준비 중
/// under its header while the others draw. In a live build the server sends
/// the trend only, and the two model-made blocks are computed on the reader's
/// device ([directionAiProvider]) from the sitting member's pledges, bills
/// and the district's threads -- or, where the model cannot run, the block
/// says so and why. Every section says what it was read from, and nothing on it ranks a
/// candidate -- the plot draws every point the same, and the issue list is
/// ordered by how often an issue came up, which is said in so many words.
class AiDirectionScreen extends ConsumerWidget {
  const AiDirectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(directionReportProvider);
    final hasAi = ref.watch(directionAiSourceProvider) != null;
    final ai = ref.watch(directionAiProvider);
    final stanceLabel =
        ref.watch(matchSubjectProvider) == MatchSubject.incumbent
        ? _incumbentStanceLabel
        : _stanceLabel;
    void retry() => ref.invalidate(directionAiProvider);

    return AiTabScaffold(
      mode: AiMode.direction,
      title: '어디로 향하고 있나',
      // No axes button in the top bar: the two views share one toolbar so
      // switching does not move it. 축 정의 공개 sits beside the plot.
      content: [
        report.when(
          loading: () => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: const InkLoadingRows(rows: 4),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: Text(
                error is NotAvailableException
                    ? '이 지역구의 방향 분석은 아직 준비 중입니다.'
                    : '분석 결과를 불러오지 못했습니다.',
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ),
          data: (data) => SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.x2,
              AppSpacing.screen,
              AppSpacing.x12 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                RevealIn(
                  child: _aiBlock<PolicyStances>(
                    fromReport: data.stances,
                    hasAi: hasAi,
                    ai: ai,
                    pick: (blocks) => blocks.stances,
                    note: (blocks) => blocks.stancesNote,
                    draw: (stances) => _StanceSection(stances: stances),
                    number: '01',
                    label: stanceLabel,
                    pendingNote: '후보 공약 문구의 정책 성향 분석은 아직 준비 중입니다.',
                    runningNote: '이 기기에서 공약 문구를 두 축으로 분류하고 있습니다.',
                    onRetry: retry,
                  ),
                ),
                const SizedBox(height: AppSpacing.x8),
                RevealIn(
                  index: 1,
                  child: switch (data.trend) {
                    final trend? => _TrendSection(trend: trend),
                    null => const _PendingSection(
                      number: '02',
                      label: _trendLabel,
                      note: '현직 의원의 대표발의 법안 집계는 아직 준비 중입니다.',
                    ),
                  },
                ),
                const SizedBox(height: AppSpacing.x8),
                RevealIn(
                  index: 2,
                  child: _aiBlock<IssueFlow>(
                    fromReport: data.issues,
                    hasAi: hasAi,
                    ai: ai,
                    pick: (blocks) => blocks.issues,
                    note: (blocks) => blocks.issuesNote,
                    draw: (flow) => _IssueSection(flow: flow),
                    number: '03',
                    label: _issueLabel,
                    pendingNote: '지역 쟁점 흐름 분석은 아직 준비 중입니다.',
                    runningNote: '이 기기에서 법안·토론 제목을 쟁점별로 분류하고 있습니다.',
                    onRetry: retry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const _stanceLabel = '후보 정책 성향';
const _incumbentStanceLabel = '현 의원 공약 성향';
const _trendLabel = '의원 행보 추세';
const _issueLabel = '지역 쟁점 흐름';

/// What the bill trend was counted from, said under the chart in place of
/// the AI label it does not carry.
const trendBasis = '대표발의 법안의 소관 위원회 기준 집계 · 위원회 미정 법안 제외';

/// One model-made block, from wherever it comes.
///
/// A fixture report carries its sample block and draws it. Otherwise the
/// block is this device's to make: running, made, not made (with the note
/// saying why), or impossible here (the model cannot run on this device).
Widget _aiBlock<T>({
  required T? fromReport,
  required bool hasAi,
  required AsyncValue<DirectionAiBlocks?> ai,
  required T? Function(DirectionAiBlocks blocks) pick,
  required String? Function(DirectionAiBlocks blocks) note,
  required Widget Function(T value) draw,
  required String number,
  required String label,
  required String pendingNote,
  required String runningNote,
  required VoidCallback onRetry,
}) {
  if (fromReport != null) {
    return draw(fromReport);
  }
  Widget pending(String text) =>
      _PendingSection(number: number, label: label, note: text);
  if (!hasAi) {
    return pending(pendingNote);
  }
  return ai.when(
    loading: () =>
        _RunningSection(number: number, label: label, note: runningNote),
    error: (_, _) => pending('기기 모델이 분석을 끝내지 못했습니다.'),
    data: (blocks) {
      if (blocks == null) {
        return pending(pendingNote);
      }
      final reason = blocks.unavailable;
      if (reason != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(number: number, label: label),
            const SizedBox(height: AppSpacing.x3),
            OnDeviceUnavailableNotice(
              reason: reason,
              compact: true,
              onRetry: onRetry,
            ),
          ],
        );
      }
      final value = pick(blocks);
      return value != null ? draw(value) : pending(note(blocks) ?? pendingNote);
    },
  );
}

/// A block the device's model is still working on: its header, and what the
/// model is reading, in words. No figure yet, so no label either.
class _RunningSection extends StatelessWidget {
  const _RunningSection({
    required this.number,
    required this.label,
    required this.note,
  });

  final String number;
  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(number: number, label: label),
        const SizedBox(height: AppSpacing.x3),
        Row(
          children: [
            const InkStampIndicator(),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                note,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A block this district has no data for yet: its header, and 준비 중 in
/// words. No label and no figure, so nothing here asks for the disclosure.
class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.number,
    required this.label,
    required this.note,
  });

  final String number;
  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(number: number, label: label),
        const SizedBox(height: AppSpacing.x3),
        Text(
          note,
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral700),
        ),
      ],
    );
  }
}

/// A section header's trailing line with the `AI 참고 자료` label before it.
///
/// The stance plot and the issue flow are model output -- a placement and a
/// classification -- so each is marked where it opens, next to the figure it
/// introduces rather than once at the top of the page. The bill trend is a
/// count and does not use this.
class _AiTrailing extends StatelessWidget {
  const _AiTrailing(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiReferenceLabel(),
        const SizedBox(width: AppSpacing.x2),
        child,
      ],
    );
  }
}

void _showAxisDefinitions(BuildContext context, PolicyStances stances) {
  PlatformAdaptiveSheet.show<void>(
    context: context,
    builder: (context) => _AxisDefinitions(stances: stances),
  );
}

// ---------------------------------------------------------------------------
// 01 후보 정책 성향

class _StanceSection extends StatelessWidget {
  const _StanceSection({required this.stances});

  final PolicyStances stances;

  @override
  Widget build(BuildContext context) {
    final counts = [
      for (final candidate in stances.candidates)
        '${candidate.name} ${candidate.pledgeCount}건',
    ].join(' · ');
    final incumbent = stances.subject == MatchSubject.incumbent;
    final onDevice = stances.onDevice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: '01',
          label: incumbent ? _incumbentStanceLabel : _stanceLabel,
          trailing: _AiTrailing(
            TextLink(
              label: '축 정의 공개 ↗',
              small: true,
              onTap: () => _showAxisDefinitions(context, stances),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3 + 2),
        _StancePlot(stances: stances),
        const SizedBox(height: AppSpacing.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onDevice != null) ...[
                    SourceLine(
                      '22대 공약 ${stances.pledgeCount}건 · $onDeviceStanceMethod',
                    ),
                    OnDeviceStamp(run: onDevice),
                  ] else ...[
                    SourceLine('등록 공약 ${stances.pledgeCount}건 문구 기준'),
                    SourceLine(counts),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Flexible(
              child: Align(
                alignment: Alignment.topRight,
                child: const MarginNote(
                  '점 크기·색은 모두 같게\n위치는 문구만 반영',
                  underline: false,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        SourceBadge(source: stances.source),
      ],
    );
  }
}

/// What each axis was defined as, published next to the plot it produced.
class _AxisDefinitions extends StatelessWidget {
  const _AxisDefinitions({required this.stances});

  final PolicyStances stances;

  @override
  Widget build(BuildContext context) {
    final axes = stances.axes;
    final title = Theme.of(context).textTheme.titleMedium;
    final body = AppTextStyles.cardBody.copyWith(
      color: AppColors.ink,
      height: 1.55,
    );

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
          Text('축 정의', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.x4),
          const SectionHeader(number: '가로', label: '축'),
          const SizedBox(height: AppSpacing.x2),
          Text('${axes.xLow} ↔ ${axes.xHigh}', style: title),
          const SizedBox(height: AppSpacing.x1),
          Text(axes.xDefinition, style: body),
          const SizedBox(height: AppSpacing.x6),
          const SectionHeader(number: '세로', label: '축'),
          const SizedBox(height: AppSpacing.x2),
          Text('${axes.yLow} ↔ ${axes.yHigh}', style: title),
          const SizedBox(height: AppSpacing.x1),
          Text(axes.yDefinition, style: body),
          const SizedBox(height: AppSpacing.x4),
          SourceBadge(source: stances.source),
        ],
      ),
    );
  }
}

/// A square plot with one hollow ink dot per candidate.
///
/// Every dot is the same size, the same ink and the same weight, and the
/// names are set the same way (N-1, N-2). The only thing that distinguishes
/// one candidate from another is where the wording put them, so that is the
/// only thing that moves: each dot travels out from the centre to its place.
class _StancePlot extends StatelessWidget {
  const _StancePlot({required this.stances});

  static const _axisGutter = 22.0;
  static const _dot = 14.0;

  final PolicyStances stances;

  String _side(double value, String low, String high) {
    if (value < -0.1) {
      return '$low 쪽';
    }
    if (value > 0.1) {
      return '$high 쪽';
    }
    return '가운데';
  }

  @override
  Widget build(BuildContext context) {
    AiDisclosureScope.require(context, widget: '_StancePlot');

    final axes = stances.axes;
    final axisStyle = AppTextStyles.disclaimer.copyWith(
      color: AppColors.neutral700,
    );
    final nameStyle = AppTextStyles.figureSmall.copyWith(
      fontSize: 14,
      color: AppColors.ink,
    );

    final description = [
      for (final candidate in stances.candidates)
        '${candidate.name}: ${_side(candidate.x, axes.xLow, axes.xHigh)}, '
            '${_side(candidate.y, axes.yLow, axes.yHigh)}',
    ].join('. ');

    final who = stances.subject == MatchSubject.incumbent
        ? '현 의원 공약의 정책 성향 위치'
        : '후보 ${stances.candidates.length}명의 정책 성향 위치';

    return Semantics(
      label:
          '$who. '
          '가로 ${axes.xLow}에서 ${axes.xHigh}, '
          '세로 ${axes.yLow}에서 ${axes.yHigh}. $description',
      container: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth;
            final plot = size - _axisGutter;
            final center = Offset(_axisGutter + plot / 2, plot / 2);

            return ExcludeSemantics(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _axisGutter,
                    top: 0,
                    width: plot,
                    height: plot,
                    child: const CustomPaint(painter: _CrosshairPainter()),
                  ),
                  // Horizontal axis ends, under the plot.
                  Positioned(
                    left: _axisGutter,
                    right: 0,
                    bottom: 0,
                    height: _axisGutter,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('← ${axes.xLow}', style: axisStyle),
                        Text('${axes.xHigh} →', style: axisStyle),
                      ],
                    ),
                  ),
                  // Vertical axis ends, read bottom to top.
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _axisGutter - 6,
                    height: plot,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(axes.yLow, style: axisStyle),
                          Text(axes.yHigh, style: axisStyle),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < stances.candidates.length; i++)
                    _StanceDot(
                      candidate: stances.candidates[i],
                      center: center,
                      target: Offset(
                        center.dx + stances.candidates[i].x * (plot / 2 - 12),
                        center.dy - stances.candidates[i].y * (plot / 2 - 12),
                      ),
                      plotRight: size,
                      index: i,
                      nameStyle: nameStyle,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StanceDot extends StatelessWidget {
  const _StanceDot({
    required this.candidate,
    required this.center,
    required this.target,
    required this.plotRight,
    required this.index,
    required this.nameStyle,
  });

  final CandidateStance candidate;
  final Offset center;
  final Offset target;
  final double plotRight;
  final int index;
  final TextStyle nameStyle;

  @override
  Widget build(BuildContext context) {
    // A name that would run off the right edge sits to the left of its dot.
    // That is layout, not emphasis: the name is set identically either way.
    final labelLeft = candidate.x > 0.4;
    const half = _StancePlot._dot / 2;

    return MotionIn(
      duration: AppMotion.slow,
      delay: AppMotion.staggerFor(index + 2),
      curve: AppMotion.sheet,
      builder: (context, t, child) {
        final at = Offset.lerp(center, target, t)!;
        return Positioned(
          left: labelLeft ? null : at.dx - half,
          right: labelLeft ? plotRight - at.dx - half : null,
          top: at.dy - 10,
          child: Opacity(opacity: t.clamp(0, 1), child: child),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: labelLeft ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: _StancePlot._dot,
            height: _StancePlot._dot,
            decoration: BoxDecoration(
              color: AppColors.ground,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ink, width: 2.2),
            ),
          ),
          const SizedBox(width: AppSpacing.x1 + 1),
          Text(candidate.name, style: nameStyle),
        ],
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.neutral100);
    final line = Paint()
      ..color = AppColors.neutral400
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        line,
      )
      ..drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        line,
      );
  }

  @override
  bool shouldRepaint(_CrosshairPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 02 의원 행보 추세

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.trend});

  final LegislatorTrend trend;

  /// How many bills each term was counted from, and how many were left out.
  String get _counts {
    final from = trend.fromCount;
    final to = trend.toCount;
    final excluded = trend.excludedCount ?? 0;
    return [
      if (from != null && to != null)
        '${trend.fromTerm} $from건 · ${trend.toTerm} $to건'
      else
        '대표발의 법안 ${trend.billCount}건',
      if (excluded > 0) '위원회 미정 $excluded건 제외',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately no AiReferenceLabel and no AiDisclosureScope.require: this
    // is a count over committee referrals, not model output, and marking it
    // as AI would misdescribe it. Its basis line says what it is instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: '02',
          label: _trendLabel,
          trailing: SourceLine('${trend.legislatorName} · 대표발의 비중'),
        ),
        const SizedBox(height: AppSpacing.x4),
        _SlopeChart(trend: trend),
        const SizedBox(height: AppSpacing.x3 + 2),
        Text(
          trend.summary,
          style: AppTextStyles.reading.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.x2),
        const SourceLine(trendBasis),
        SourceLine(_counts),
        SourceBadge(source: trend.source),
      ],
    );
  }
}

/// Each field's share of bills in one term, joined to its share in the next.
///
/// The field with the largest share in the later term is set in ink, because
/// it is the one the summary under the chart names; the rest are grey. The
/// lines draw themselves left to right, one after another. A term with no
/// counted bills has no dots at all and says 집계 없음 under its heading,
/// rather than a column of zeros.
class _SlopeChart extends StatelessWidget {
  const _SlopeChart({required this.trend});

  final LegislatorTrend trend;

  static String _share(double? value) =>
      value == null ? '집계 없음' : '${value.round()}%';

  @override
  Widget build(BuildContext context) {
    final fields = trend.fields;
    final description = [
      for (final field in fields)
        '${field.label} ${_share(field.from)}에서 ${_share(field.to)}',
    ].join(', ');
    final base = DefaultTextStyle.of(context).style;

    return Semantics(
      label:
          '분야별 대표발의 비중 ${trend.fromTerm}에서 ${trend.toTerm}로: '
          '$description',
      excludeSemantics: true,
      child: SizedBox(
        // Room for every label once they are pushed apart.
        height: math.max(180, 48.0 + fields.length * _SlopePainter._labelGap),
        child: MotionIn(
          duration: AppMotion.slow,
          delay: AppMotion.staggerFor(2),
          curve: AppMotion.ink,
          builder: (context, t, _) => CustomPaint(
            size: Size.infinite,
            painter: _SlopePainter(
              fields: fields,
              leading: trend.leading,
              fromTerm: trend.fromTerm,
              toTerm: trend.toTerm,
              progress: t,
              headingStyle: base.merge(
                AppTextStyles.figureSmall.copyWith(
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
              labelStyle: base.merge(
                AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
              ),
              leadingLabelStyle: base.merge(
                AppTextStyles.statLabel.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlopePainter extends CustomPainter {
  _SlopePainter({
    required this.fields,
    required this.leading,
    required this.fromTerm,
    required this.toTerm,
    required this.progress,
    required this.headingStyle,
    required this.labelStyle,
    required this.leadingLabelStyle,
  });

  static const _labelGap = 15.0;

  final List<FieldShare> fields;
  final FieldShare? leading;
  final String fromTerm;
  final String toTerm;
  final double progress;
  final TextStyle headingStyle;
  final TextStyle labelStyle;
  final TextStyle leadingLabelStyle;

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Pushes labels apart so two close values do not print on top of each
  /// other. The dots stay where the values are; only the words move. A field
  /// with no value in this term has no label and keeps its null.
  List<double?> _spread(List<double?> ys, double bottom) {
    final order = [
      for (var i = 0; i < ys.length; i++)
        if (ys[i] != null) i,
    ]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
    final out = List.of(ys);
    for (var k = 1; k < order.length; k++) {
      final prev = out[order[k - 1]]!;
      if (out[order[k]]! - prev < _labelGap) {
        out[order[k]] = prev + _labelGap;
      }
    }
    // If that pushed the last one off the bottom, shift the stack back up.
    final overflow = order.isEmpty ? 0.0 : out[order.last]! - bottom;
    if (overflow > 0) {
      for (final i in order) {
        out[i] = out[i]! - overflow;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final f in fields) ...[?f.from, ?f.to],
    ];
    if (values.isEmpty) {
      return;
    }

    const top = 32.0;
    final bottom = size.height - 10;
    // Each side is as wide as its longest label needs (법사·행정 38% is wider
    // than the chart's default gutter), so no label runs off the edge.
    double widest(Iterable<String> labels) => labels.fold(
      0,
      (width, label) =>
          math.max(width, _text(label, leadingLabelStyle).width + 12),
    );
    final gutter = math.min(76.0, size.width * 0.24);
    final leftX = math.max(
      gutter,
      widest([
        for (final f in fields)
          if (f.from != null) '${f.label} ${f.from!.round()}%',
      ]),
    );
    final rightX =
        size.width -
        math.max(
          gutter,
          widest([
            for (final f in fields)
              if (f.to != null) '${f.to!.round()}% ${f.label}',
          ]),
        );

    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low == 0 ? 1 : high - low;
    double yOf(double v) => top + (high - v) / span * (bottom - top);
    double? yOrNull(double? v) => v == null ? null : yOf(v);

    for (final (x, term, present) in [
      (leftX, fromTerm, fields.any((f) => f.from != null)),
      (rightX, toTerm, fields.any((f) => f.to != null)),
    ]) {
      final heading = _text(term, headingStyle);
      heading.paint(canvas, Offset(x - heading.width / 2, 0));
      if (!present) {
        // Said in words, not left as a blank that could read as zero.
        final none = _text('집계 없음', labelStyle);
        none.paint(canvas, Offset(x - none.width / 2, heading.height + 4));
      }
    }

    final leftYs = _spread([for (final f in fields) yOrNull(f.from)], bottom);
    final rightYs = _spread([for (final f in fields) yOrNull(f.to)], bottom);

    // Grey lines first so the ink one is drawn over them where they cross.
    final order = [
      for (var i = 0; i < fields.length; i++)
        if (fields[i] != leading) i,
      for (var i = 0; i < fields.length; i++)
        if (fields[i] == leading) i,
    ];

    for (final i in order) {
      final field = fields[i];
      final isLeading = field == leading;
      final color = isLeading ? AppColors.ink : AppColors.neutral500;
      final style = isLeading ? leadingLabelStyle : labelStyle;

      // Each line starts a little after the one before it.
      final stagger = fields.length <= 1 ? 0.0 : 0.3 * i / (fields.length - 1);
      final t = ((progress - stagger) / (1 - 0.3)).clamp(0.0, 1.0);
      if (t <= 0) {
        continue;
      }

      final fromShare = field.from;
      final toShare = field.to;
      final from = fromShare == null ? null : Offset(leftX, yOf(fromShare));
      final to = toShare == null ? null : Offset(rightX, yOf(toShare));
      final dot = Paint()..color = color;

      if (from != null) {
        canvas.drawCircle(from, 3.5, dot);
        final left = _text('${field.label} ${fromShare!.round()}%', style);
        left.paint(
          canvas,
          Offset(from.dx - 10 - left.width, leftYs[i]! - left.height / 2),
        );
      }

      // A line only joins two points; a field with one term is a lone dot.
      if (from != null && to != null) {
        canvas.drawLine(
          from,
          Offset.lerp(from, to, t)!,
          Paint()
            ..color = color
            ..strokeWidth = isLeading ? 2.6 : 1.6
            ..strokeCap = StrokeCap.round,
        );
      }

      if (to != null && (from == null || t >= 1)) {
        canvas.drawCircle(to, 3.5, dot);
        final right = _text('${toShare!.round()}% ${field.label}', style);
        right.paint(canvas, Offset(to.dx + 10, rightYs[i]! - right.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_SlopePainter old) =>
      old.progress != progress ||
      old.fields != fields ||
      old.leading != leading ||
      old.labelStyle != labelStyle;
}

// ---------------------------------------------------------------------------
// 03 지역 쟁점 흐름

class _IssueSection extends StatelessWidget {
  const _IssueSection({required this.flow});

  final IssueFlow flow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: '03',
          label: _issueLabel,
          trailing: _AiTrailing(SourceLine(flow.period)),
        ),
        const SizedBox(height: AppSpacing.x2),
        for (var i = 0; i < flow.issues.length; i++)
          _IssueRow(issue: flow.issues[i], index: i),
        const SizedBox(height: AppSpacing.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceLine(flow.basis),
                  if (flow.onDevice != null) OnDeviceStamp(run: flow.onDevice!),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Flexible(
              child: Align(
                alignment: Alignment.topRight,
                child: const MarginNote(
                  '언급 많은 순, 좋고 나쁨 아님',
                  underline: false,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        SourceBadge(source: flow.source),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.index});

  final LocalIssue issue;
  final int index;

  @override
  Widget build(BuildContext context) {
    AiDisclosureScope.require(context, widget: '_IssueRow');

    final direction = issue.direction;
    final peak = issue.monthly.reduce(math.max);
    final count = issue.monthly.length;

    return MergeSemantics(
      child: RuledRow(
        minHeight: 60,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.label,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${direction.glyph} ${direction.label}',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            ExcludeSemantics(
              child: SizedBox(
                width: 62,
                height: 24,
                child: DrawnLine(
                  strokeWidth: 1.6,
                  delay: AppMotion.staggerFor(index + 3),
                  points: [
                    for (var i = 0; i < count; i++)
                      Offset(
                        i / (count - 1),
                        peak == 0 ? 0 : issue.monthly[i] / peak,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            SizedBox(
              width: 64,
              child: Align(
                alignment: Alignment.centerRight,
                child: Figure(
                  value: issue.mentions,
                  unit: '건',
                  delay: AppMotion.staggerFor(index + 3),
                  style: AppTextStyles.figureSmall.copyWith(
                    color: AppColors.ink,
                  ),
                  unitStyle: AppTextStyles.figureUnit.copyWith(
                    fontSize: 12,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
