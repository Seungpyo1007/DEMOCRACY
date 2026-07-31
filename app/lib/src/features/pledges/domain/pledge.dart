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
    );
  }

  final String id;
  final String title;
  final String category;
  final PledgeStatus status;
  final SourceMetadata source;
  final Uri? evidenceUrl;
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
}
