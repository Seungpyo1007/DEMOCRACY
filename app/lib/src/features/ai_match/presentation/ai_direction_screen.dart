import 'dart:math' as math;

import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Direction analysis: where the candidates' pledges sit, how the incumbent's
/// bills have moved, which local issues are rising.
///
/// The same disclosure as the match, because it is the same kind of output:
/// the model read wording and placed it. Every section says what it was read
/// from, and nothing on it ranks a candidate -- the plot draws every point the
/// same, and the issue list is ordered by how often an issue came up, which is
/// said in so many words.
class AiDirectionScreen extends ConsumerWidget {
  const AiDirectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(directionReportProvider);

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
              child: Center(child: PlatformAdaptiveProgress.circular(context)),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: Text(
                error is NotAvailableException
                    ? '이 지역구의 AI 분석은 아직 준비 중입니다.'
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
                RevealIn(child: _StanceSection(stances: data.stances)),
                const SizedBox(height: AppSpacing.x8),
                RevealIn(index: 1, child: _TrendSection(trend: data.trend)),
                const SizedBox(height: AppSpacing.x8),
                RevealIn(index: 2, child: _IssueSection(flow: data.issues)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A section header's trailing line with the `AI 참고 자료` label before it.
///
/// All three sections are model output -- a placement, a summary, a
/// classification -- so each one is marked where it opens, next to the
/// figure it introduces rather than once at the top of the page.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: '01',
          label: '후보 정책 성향',
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
                  SourceLine('등록 공약 ${stances.pledgeCount}건 문구 기준'),
                  SourceLine(counts),
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

    return Semantics(
      label:
          '후보 ${stances.candidates.length}명의 정책 성향 위치. '
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
      duration: AppMotion.emphasized,
      delay: AppMotion.staggerFor(index + 2),
      curve: AppMotion.emphasizedCurve,
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

  @override
  Widget build(BuildContext context) {
    AiDisclosureScope.require(context, widget: '_TrendSection');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          number: '02',
          label: '의원 행보 추세',
          trailing: _AiTrailing(SourceLine('${trend.legislatorName} · 발의 비중')),
        ),
        const SizedBox(height: AppSpacing.x4),
        _SlopeChart(trend: trend),
        const SizedBox(height: AppSpacing.x3 + 2),
        Text(
          trend.summary,
          style: AppTextStyles.reading.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.x2),
        SourceLine('발의 법안 ${trend.billCount}건 · AI 요약'),
        SourceBadge(source: trend.source),
      ],
    );
  }
}

/// Each field's share of bills in one term, joined to its share in the next.
///
/// The field with the largest share in the later term is set in ink, because
/// it is the one the summary under the chart names; the rest are grey. The
/// lines draw themselves left to right, one after another.
class _SlopeChart extends StatelessWidget {
  const _SlopeChart({required this.trend});

  final LegislatorTrend trend;

  @override
  Widget build(BuildContext context) {
    final fields = trend.fields;
    final description = [
      for (final field in fields)
        '${field.label} ${field.from.round()}에서 ${field.to.round()}',
    ].join(', ');
    final base = DefaultTextStyle.of(context).style;

    return Semantics(
      label:
          '분야별 발의 비중 ${trend.fromTerm}에서 ${trend.toTerm}로: '
          '$description',
      excludeSemantics: true,
      child: SizedBox(
        height: 180,
        child: MotionIn(
          duration: AppMotion.data,
          delay: AppMotion.staggerFor(2),
          curve: AppMotion.drawCurve,
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
  /// other. The dots stay where the values are; only the words move.
  List<double> _spread(List<double> ys, double bottom) {
    final order = List.generate(ys.length, (i) => i)
      ..sort((a, b) => ys[a].compareTo(ys[b]));
    final out = List.of(ys);
    for (var k = 1; k < order.length; k++) {
      final prev = out[order[k - 1]];
      if (out[order[k]] - prev < _labelGap) {
        out[order[k]] = prev + _labelGap;
      }
    }
    // If that pushed the last one off the bottom, shift the stack back up.
    final overflow = order.isEmpty ? 0.0 : out[order.last] - bottom;
    if (overflow > 0) {
      for (var i = 0; i < out.length; i++) {
        out[i] -= overflow;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fields.isEmpty) {
      return;
    }

    const top = 32.0;
    final bottom = size.height - 10;
    final leftX = math.min(76.0, size.width * 0.24);
    final rightX = size.width - leftX;

    final values = [
      for (final f in fields) ...[f.from, f.to],
    ];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low == 0 ? 1 : high - low;
    double yOf(double v) => top + (high - v) / span * (bottom - top);

    for (final (x, term) in [(leftX, fromTerm), (rightX, toTerm)]) {
      final heading = _text(term, headingStyle);
      heading.paint(canvas, Offset(x - heading.width / 2, 0));
    }

    final leftYs = _spread([for (final f in fields) yOf(f.from)], bottom);
    final rightYs = _spread([for (final f in fields) yOf(f.to)], bottom);

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

      final from = Offset(leftX, yOf(field.from));
      final to = Offset(rightX, yOf(field.to));
      final end = Offset.lerp(from, to, t)!;

      final dot = Paint()..color = color;
      canvas
        ..drawLine(
          from,
          end,
          Paint()
            ..color = color
            ..strokeWidth = isLeading ? 2.6 : 1.6
            ..strokeCap = StrokeCap.round,
        )
        ..drawCircle(from, 3.5, dot);

      final left = _text('${field.label} ${field.from.round()}%', style);
      left.paint(
        canvas,
        Offset(from.dx - 10 - left.width, leftYs[i] - left.height / 2),
      );

      if (t >= 1) {
        canvas.drawCircle(to, 3.5, dot);
        final right = _text('${field.to.round()}% ${field.label}', style);
        right.paint(canvas, Offset(to.dx + 10, rightYs[i] - right.height / 2));
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
          label: '지역 쟁점 흐름',
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
                children: [SourceLine(flow.basis)],
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
                child: CountUp(
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
