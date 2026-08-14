import 'package:democracy/src/core/provenance/source_metadata.dart';

/// Where a pledge stands.
///
/// The product rules require status to be carried by colour, icon and text
/// together, so the icon and label travel with the value and no caller can
/// render the colour alone.
enum PledgeStatus {
  fulfilled(label: '이행 완료', glyph: '✓'),
  inProgress(label: '진행 중', glyph: '◐'),
  unfulfilled(label: '미이행', glyph: '—'),
  reversed(label: '번복', glyph: '↩');

  const PledgeStatus({required this.label, required this.glyph});

  final String label;
  final String glyph;

  /// Never colour-only: the glyph and the word are always present.
  String get display => '$glyph $label';

  static PledgeStatus parse(Object? raw) {
    return switch (raw) {
      'fulfilled' => PledgeStatus.fulfilled,
      'inProgress' => PledgeStatus.inProgress,
      'reversed' => PledgeStatus.reversed,
      _ => PledgeStatus.unfulfilled,
    };
  }
}

class Pledge {
  const Pledge({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.source,
    this.evidenceUrl,
    this.judgement,
  });

  factory Pledge.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String || title.isEmpty) {
      throw MissingSourceException(
        field: 'pledge',
        reason: 'id and title are required.',
      );
    }

    final rawEvidence = json['evidenceUrl'];
    final status = PledgeStatus.parse(json['status']);
    final evidenceUrl = rawEvidence is String
        ? Uri.tryParse(rawEvidence)
        : null;

    // A reversal is the one judgement the spec says must always be traceable
    // back to the original wording, so it cannot ship without that link.
    if (status == PledgeStatus.reversed && evidenceUrl == null) {
      throw MissingSourceException(
        field: 'pledge.$id',
        reason: 'A reversed pledge requires evidenceUrl.',
      );
    }

    return Pledge(
      id: id,
      title: title,
      category: json['category'] as String? ?? '',
      status: status,
      evidenceUrl: evidenceUrl,
      source: SourceMetadata.fromJson(json['source'], field: 'pledge.$id'),
      judgement: PledgeJudgement.fromJson(
        json['judgement'],
        field: 'pledge.$id.judgement',
      ),
    );
  }

  final String id;
  final String title;
  final String category;
  final PledgeStatus status;
  final SourceMetadata source;
  final Uri? evidenceUrl;

  /// How this pledge came to carry the status it has. Null until the pipeline
  /// has produced one -- and its absence is itself worth showing, since a
  /// status with no recorded reasoning is a status nobody can argue with.
  final PledgeJudgement? judgement;
}

/// One step of the pipeline that decided a pledge's status.
class JudgementStep {
  const JudgementStep({
    required this.actor,
    required this.detail,
    required this.stamp,
  });

  factory JudgementStep.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'judgementStep',
        reason: 'A step must be an object.',
      );
    }

    final actor = json['actor'];
    if (actor is! String || actor.isEmpty) {
      throw const MissingSourceException(
        field: 'judgementStep',
        reason: 'A step needs an actor -- who judged is the point.',
      );
    }

    return JudgementStep(
      actor: actor,
      detail: json['detail'] is String ? json['detail']! as String : '',
      stamp: json['stamp'] is String ? json['stamp']! as String : '',
    );
  }

  final String actor;
  final String detail;
  final String stamp;
}

/// The record of who decided, on what, and when.
///
/// The tracker exists to answer "who judged this and how", so the steps are
/// part of the payload rather than something the screen narrates.
class PledgeJudgement {
  const PledgeJudgement({required this.steps, required this.source});

  static PledgeJudgement? fromJson(Object? json, {required String field}) {
    if (json is! Map) {
      return null;
    }

    final raw = json['steps'];
    final steps = List<JudgementStep>.unmodifiable(
      raw is List ? raw.map(JudgementStep.fromJson) : const <JudgementStep>[],
    );

    if (steps.isEmpty) {
      return null;
    }

    return PledgeJudgement(
      steps: steps,
      source: SourceMetadata.fromJson(json['source'], field: field),
    );
  }

  final List<JudgementStep> steps;
  final SourceMetadata source;
}

/// A category's fulfilment, as one bar on the tracker.
class CategoryRate {
  const CategoryRate({
    required this.category,
    required this.fulfilled,
    required this.total,
  });

  final String category;
  final int fulfilled;
  final int total;

  /// Fulfilled over total, and nothing else. Counting a pledge in progress as
  /// a fraction of a kept one would be the app deciding how much credit
  /// partial work earns, which is a judgement it has no standing to make.
  double get share => total == 0 ? 0 : fulfilled / total;

  String get display => '${(share * 100).round()}%';
}

/// A district's pledges plus the totals the home card summarises.
class PledgeBoard {
  const PledgeBoard({required this.pledges, required this.source});

  factory PledgeBoard.fromJson(Map<String, Object?> json) {
    final rawPledges = json['pledges'];
    return PledgeBoard(
      pledges: List.unmodifiable(<Pledge>[
        if (rawPledges is List)
          for (final pledge in rawPledges)
            Pledge.fromJson(pledge as Map<String, Object?>),
      ]),
      source: SourceMetadata.fromJson(json['source'], field: 'pledgeBoard'),
    );
  }

  final List<Pledge> pledges;
  final SourceMetadata source;

  int get total => pledges.length;

  int countOf(PledgeStatus status) =>
      pledges.where((pledge) => pledge.status == status).length;

  double shareOf(PledgeStatus status) =>
      total == 0 ? 0 : countOf(status) / total;

  /// The headline the donut sits around.
  ///
  /// Same rule as [CategoryRate.share]: kept over promised. The figure the
  /// dashboard shows comes from the assembly's own feed and may differ; this
  /// one is derived here and says so by living on the board.
  double get fulfilmentRate => shareOf(PledgeStatus.fulfilled);

  String get fulfilmentDisplay => '${(fulfilmentRate * 100).round()}%';

  /// Categories in descending fulfilment, which is the order the guide draws
  /// them and the only ordering that is about the data rather than about
  /// whoever happens to be listed first.
  List<CategoryRate> get categories {
    final counts = <String, (int, int)>{};
    for (final pledge in pledges) {
      if (pledge.category.isEmpty) {
        continue;
      }
      final (fulfilled, total) = counts[pledge.category] ?? (0, 0);
      counts[pledge.category] = (
        fulfilled + (pledge.status == PledgeStatus.fulfilled ? 1 : 0),
        total + 1,
      );
    }

    final rates = [
      for (final entry in counts.entries)
        CategoryRate(
          category: entry.key,
          fulfilled: entry.value.$1,
          total: entry.value.$2,
        ),
    ]..sort((a, b) => b.share.compareTo(a.share));

    return List.unmodifiable(rates);
  }

  Pledge? byId(String id) {
    for (final pledge in pledges) {
      if (pledge.id == id) {
        return pledge;
      }
    }
    return null;
  }
}
