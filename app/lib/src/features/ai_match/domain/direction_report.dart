import 'package:democracy/src/core/provenance/source_metadata.dart';

/// The two axes the policy-position plot is drawn on, and what each end means.
///
/// Published with the result rather than hard-coded in the screen: where a
/// candidate lands is only checkable if the reader can see what the axis was
/// defined as, and a definition that lives in the widget can change without
/// the data knowing.
class StanceAxes {
  const StanceAxes({
    required this.xLow,
    required this.xHigh,
    required this.yLow,
    required this.yHigh,
    required this.xDefinition,
    required this.yDefinition,
  });

  factory StanceAxes.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Stance axes must be an object.');
    }

    String read(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Stance axes need "$key".');
      }
      return value;
    }

    return StanceAxes(
      xLow: read('xLow'),
      xHigh: read('xHigh'),
      yLow: read('yLow'),
      yHigh: read('yHigh'),
      xDefinition: read('xDefinition'),
      yDefinition: read('yDefinition'),
    );
  }

  /// The left end of the horizontal axis, e.g. 성장 중심.
  final String xLow;
  final String xHigh;

  /// The bottom end of the vertical axis, e.g. 규제 강화.
  final String yLow;
  final String yHigh;

  /// How the wording was scored on each axis, in a sentence.
  final String xDefinition;
  final String yDefinition;
}

/// Where one candidate's registered pledges sit on the two axes.
///
/// Carries nothing that could tell candidates apart visually -- no party, no
/// rank, no colour. Every point is drawn the same (N-1, N-2); the only thing
/// that differs between them is the position the wording put them in.
class CandidateStance {
  const CandidateStance({
    required this.candidateId,
    required this.name,
    required this.x,
    required this.y,
    required this.pledgeCount,
  });

  factory CandidateStance.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A stance must be an object.');
    }

    final id = json['candidateId'];
    final name = json['name'];
    final x = json['x'];
    final y = json['y'];
    final count = json['pledgeCount'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        x is! num ||
        y is! num ||
        count is! int) {
      throw const FormatException(
        'A stance needs a candidate, a name, both coordinates and a count.',
      );
    }

    return CandidateStance(
      candidateId: id,
      name: name,
      x: x.toDouble().clamp(-1, 1),
      y: y.toDouble().clamp(-1, 1),
      pledgeCount: count,
    );
  }

  final String candidateId;
  final String name;

  /// -1 (the axis's low end) to 1 (its high end).
  final double x;
  final double y;

  /// How many registered pledges the position was read from.
  final int pledgeCount;
}

/// 01 -- where each candidate's pledge wording sits.
class PolicyStances {
  const PolicyStances({
    required this.axes,
    required this.candidates,
    required this.source,
  });

  factory PolicyStances.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Policy stances must be an object.');
    }

    final raw = json['candidates'];
    final candidates = [
      if (raw is List)
        for (final candidate in raw) CandidateStance.fromJson(candidate),
      // 가나다 order, whatever order the payload used (N-2). Sorting by
      // position or count would put one candidate first for a reason.
    ]..sort((a, b) => a.name.compareTo(b.name));

    return PolicyStances(
      axes: StanceAxes.fromJson(json['axes']),
      candidates: List.unmodifiable(candidates),
      source: SourceMetadata.fromJson(
        json['source'],
        field: 'direction.stance',
      ),
    );
  }

  final StanceAxes axes;
  final List<CandidateStance> candidates;
  final SourceMetadata source;

  /// Every pledge the plot was read from, across candidates.
  int get pledgeCount =>
      candidates.fold(0, (sum, candidate) => sum + candidate.pledgeCount);
}

/// One policy field's share of the incumbent's bills in two terms.
class FieldShare {
  const FieldShare({required this.label, required this.from, required this.to});

  factory FieldShare.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A field share must be an object.');
    }

    final label = json['label'];
    final from = json['from'];
    final to = json['to'];
    if (label is! String || label.isEmpty || from is! num || to is! num) {
      throw const FormatException('A field share needs a label and two terms.');
    }

    return FieldShare(
      label: label,
      from: from.toDouble().clamp(0, 100),
      to: to.toDouble().clamp(0, 100),
    );
  }

  final String label;

  /// Percent of bills in the earlier term.
  final double from;

  /// Percent of bills in the later term.
  final double to;
}

/// 02 -- how the incumbent's bills have shifted between terms.
class LegislatorTrend {
  const LegislatorTrend({
    required this.legislatorName,
    required this.fromTerm,
    required this.toTerm,
    required this.billCount,
    required this.fields,
    required this.summary,
    required this.source,
  });

  factory LegislatorTrend.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A legislator trend must be an object.');
    }

    final name = json['legislatorName'];
    final fromTerm = json['fromTerm'];
    final toTerm = json['toTerm'];
    final billCount = json['billCount'];
    final summary = json['summary'];
    if (name is! String ||
        fromTerm is! String ||
        toTerm is! String ||
        billCount is! int ||
        summary is! String) {
      throw const FormatException(
        'A legislator trend needs a name, both terms, a count and a summary.',
      );
    }

    final raw = json['fields'];

    return LegislatorTrend(
      legislatorName: name,
      fromTerm: fromTerm,
      toTerm: toTerm,
      billCount: billCount,
      fields: List.unmodifiable([
        if (raw is List)
          for (final field in raw) FieldShare.fromJson(field),
      ]),
      summary: summary,
      source: SourceMetadata.fromJson(json['source'], field: 'direction.trend'),
    );
  }

  final String legislatorName;
  final String fromTerm;
  final String toTerm;

  /// How many bills the shares were counted from.
  final int billCount;

  final List<FieldShare> fields;

  /// The model's description of the shift. Descriptive only (N-5): it says
  /// which share grew, never whether that was the right thing to do.
  final String summary;

  final SourceMetadata source;

  /// The field with the largest share in the later term -- the one line the
  /// chart sets in ink, because it is the one the summary names.
  FieldShare? get leading =>
      fields.isEmpty ? null : fields.reduce((a, b) => b.to > a.to ? b : a);
}

/// Which way a local issue's mentions have gone over the period.
enum IssueDirection {
  rising('↗', '언급 늘어남'),
  steady('→', '비슷함'),
  falling('↘', '언급 줄어듦');

  const IssueDirection(this.glyph, this.label);

  final String glyph;
  final String label;
}

/// One local issue and how often it came up, month by month.
class LocalIssue {
  const LocalIssue({required this.label, required this.monthly});

  factory LocalIssue.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A local issue must be an object.');
    }

    final label = json['label'];
    final raw = json['monthly'];
    if (label is! String ||
        label.isEmpty ||
        raw is! List ||
        raw.length < 2 ||
        raw.any((count) => count is! int || count < 0)) {
      throw const FormatException(
        'A local issue needs a label and at least two monthly counts.',
      );
    }

    return LocalIssue(
      label: label,
      monthly: List.unmodifiable(raw.cast<int>()),
    );
  }

  /// Band either side of "the same" before a change counts as one. A month's
  /// wobble in a small count is not a trend, and calling it one would be the
  /// kind of claim N-5 rules out.
  static const _steadyBand = 0.2;

  final String label;

  /// Mentions per month, oldest first.
  final List<int> monthly;

  /// Every mention in the period. Derived, so it cannot disagree with the
  /// line drawn next to it.
  int get mentions => monthly.fold(0, (sum, count) => sum + count);

  /// Derived from the counts rather than read from the payload, for the same
  /// reason as [mentions]: a label and a line that can disagree eventually
  /// will. Compares the first and last thirds, so one odd month moves nothing.
  IssueDirection get direction {
    final third = (monthly.length / 3).ceil();
    double mean(Iterable<int> counts) =>
        counts.fold(0, (sum, count) => sum + count) / counts.length;

    final early = mean(monthly.take(third));
    final late = mean(monthly.skip(monthly.length - third));
    if (early == 0) {
      return late == 0 ? IssueDirection.steady : IssueDirection.rising;
    }

    final change = (late - early) / early;
    if (change > _steadyBand) {
      return IssueDirection.rising;
    }
    if (change < -_steadyBand) {
      return IssueDirection.falling;
    }
    return IssueDirection.steady;
  }
}

/// 03 -- which local issues are being talked about, most-mentioned first.
class IssueFlow {
  const IssueFlow({
    required this.period,
    required this.basis,
    required this.issues,
    required this.source,
  });

  factory IssueFlow.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('An issue flow must be an object.');
    }

    final period = json['period'];
    final basis = json['basis'];
    if (period is! String || basis is! String) {
      throw const FormatException('An issue flow needs a period and a basis.');
    }

    final raw = json['issues'];
    final issues = [
      if (raw is List)
        for (final issue in raw) LocalIssue.fromJson(issue),
      // Most-mentioned first. That is the only order the screen claims, and
      // the margin note says it is not a ranking of good and bad.
    ]..sort((a, b) => b.mentions.compareTo(a.mentions));

    return IssueFlow(
      period: period,
      basis: basis,
      issues: List.unmodifiable(issues),
      source: SourceMetadata.fromJson(
        json['source'],
        field: 'direction.issues',
      ),
    );
  }

  /// `최근 6개월`.
  final String period;

  /// What was counted: `법안 · 민원 · 지역 보도 기준`.
  final String basis;

  final List<LocalIssue> issues;
  final SourceMetadata source;
}

/// The whole direction analysis for one district.
class DirectionReport {
  const DirectionReport({
    required this.stances,
    required this.trend,
    required this.issues,
    required this.generatedAt,
  });

  factory DirectionReport.fromJson(Map<String, Object?> json) {
    final generated = json['generatedAt'];

    return DirectionReport(
      stances: PolicyStances.fromJson(json['stances']),
      trend: LegislatorTrend.fromJson(json['trend']),
      issues: IssueFlow.fromJson(json['issues']),
      generatedAt: generated is String
          ? DateTime.tryParse(generated)?.toUtc()
          : null,
    );
  }

  final PolicyStances stances;
  final LegislatorTrend trend;
  final IssueFlow issues;
  final DateTime? generatedAt;
}

abstract interface class DirectionRepository {
  Future<DirectionReport> loadReport(String districtId);
}
