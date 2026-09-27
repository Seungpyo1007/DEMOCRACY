import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';

/// One dated event in the district's own chronology.
///
/// [year] is nullable on purpose. A chronology assembled from a district
/// office's records has items whose date has not been confirmed yet, and a
/// guessed year printed in a serif would read as a fact. The screen says the
/// year is unknown instead.
class RegionEvent {
  const RegionEvent({required this.year, required this.title, this.detail});

  factory RegionEvent.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'region.event',
        reason: 'An event must be an object.',
      );
    }

    final title = json['title'];
    if (title is! String || title.isEmpty) {
      throw const MissingSourceException(
        field: 'region.event',
        reason: 'An event needs a title.',
      );
    }

    final year = json['year'];
    if (year != null && year is! int) {
      throw MissingSourceException(
        field: 'region.event',
        reason: 'year "$year" is neither a year nor null.',
      );
    }

    final detail = json['detail'];
    return RegionEvent(
      year: year as int?,
      title: title,
      detail: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  final int? year;
  final String title;
  final String? detail;
}

/// The district's chronology, attributed as a whole.
class RegionTimeline {
  const RegionTimeline({required this.events, required this.source});

  factory RegionTimeline.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'region',
        reason: 'The region block is required.',
      );
    }

    final raw = json['events'];
    return RegionTimeline(
      events: List.unmodifiable(
        raw is List ? raw.map(RegionEvent.fromJson) : const <RegionEvent>[],
      ),
      source: SourceMetadata.fromJson(json['source'], field: 'region'),
    );
  }

  final List<RegionEvent> events;
  final SourceMetadata source;
}

/// Whoever won a past election here. Name and party only -- the same shape
/// the rest of the app gives a person, with no room for a colour.
class ElectionWinner {
  const ElectionWinner({
    required this.id,
    required this.name,
    required this.party,
  });

  final String id;
  final String name;
  final PartyRef party;
}

/// One general election in this district.
///
/// An election still being counted has no winner and no share; that is the
/// row that hands off to the results tab rather than a row with blanks.
class ElectionRow {
  const ElectionRow({
    required this.term,
    required this.year,
    this.winner,
    this.share,
    this.ongoing = false,
  });

  factory ElectionRow.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'election',
        reason: 'An election row must be an object.',
      );
    }

    final term = json['term'];
    final year = json['year'];
    if (term is! int || year is! int) {
      throw const MissingSourceException(
        field: 'election',
        reason: 'An election needs a term and a year.',
      );
    }

    if (json['ongoing'] == true) {
      return ElectionRow(term: term, year: year, ongoing: true);
    }

    final winner = json['winner'];
    final share = json['share'];
    if (winner is! Map ||
        winner['name'] is! String ||
        (winner['name'] as String).isEmpty ||
        share is! num) {
      throw MissingSourceException(
        field: 'election.$term',
        reason: 'A decided election needs a winner and a vote share.',
      );
    }

    final name = winner['name'] as String;
    return ElectionRow(
      term: term,
      year: year,
      winner: ElectionWinner(
        // Falls back to the name so a feed without ids can still be matched,
        // at the cost of treating namesakes as one person.
        id: winner['id'] is String ? winner['id'] as String : name,
        name: name,
        party: PartyRef(name: winner['party'] as String? ?? '무소속'),
      ),
      share: share.toDouble(),
    );
  }

  /// `20` for 제20대.
  final int term;
  final int year;
  final ElectionWinner? winner;

  /// The winner's share of the vote, in percent.
  final double? share;
  final bool ongoing;

  String get termLabel => '제$term대';
}

/// Every election on record, with the one source they were read from.
class ElectionHistory {
  const ElectionHistory({required this.rows, required this.source, this.basis});

  factory ElectionHistory.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'elections',
        reason: 'The elections block is required.',
      );
    }

    final raw = json['rows'];
    final rows = <ElectionRow>[
      if (raw is List) ...raw.map(ElectionRow.fromJson),
    ]..sort((a, b) => a.year.compareTo(b.year));

    final basis = json['basis'];
    return ElectionHistory(
      rows: List.unmodifiable(rows),
      source: SourceMetadata.fromJson(json['source'], field: 'elections'),
      basis: basis is String && basis.isNotEmpty ? basis : null,
    );
  }

  /// Oldest first.
  final List<ElectionRow> rows;
  final SourceMetadata source;

  /// What the share is a share of, e.g. `득표율은 당선자 기준`.
  final String? basis;

  /// The elections that have a result, oldest first: what the chart draws.
  List<ElectionRow> get decided =>
      rows.where((row) => !row.ongoing).toList(growable: false);

  /// The year [winnerId] first won here, or null if they never have.
  ///
  /// Computed rather than stored so the "첫 당선" note can never disagree with
  /// the rows it annotates.
  int? firstWinYear(String winnerId) {
    for (final row in rows) {
      if (row.winner?.id == winnerId) {
        return row.year;
      }
    }
    return null;
  }
}

/// One entry in the incumbent's chronicle: an election, or a bill's stage.
///
/// [mark] is whatever the left column shows -- `2020`, `5월` -- kept as the
/// source's own wording rather than parsed into a date the feed never gave.
class ChronicleEvent {
  const ChronicleEvent({required this.mark, required this.title, this.detail});

  factory ChronicleEvent.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'legislator.event',
        reason: 'An event must be an object.',
      );
    }

    final mark = json['mark'];
    final title = json['title'];
    if (mark is! String || mark.isEmpty || title is! String || title.isEmpty) {
      throw const MissingSourceException(
        field: 'legislator.event',
        reason: 'An event needs a mark and a title.',
      );
    }

    final detail = json['detail'];
    return ChronicleEvent(
      mark: mark,
      title: title,
      detail: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  final String mark;
  final String title;
  final String? detail;
}

/// The incumbent and what they have done in the seat, in order.
class LegislatorChronicle {
  const LegislatorChronicle({
    required this.id,
    required this.name,
    required this.party,
    required this.summary,
    required this.events,
    required this.source,
    this.portraitUrl,
  });

  factory LegislatorChronicle.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'legislator',
        reason: 'The legislator block is required.',
      );
    }

    final incumbent = json['incumbent'];
    if (incumbent is! Map ||
        incumbent['id'] is! String ||
        incumbent['name'] is! String) {
      throw const MissingSourceException(
        field: 'legislator',
        reason: 'The incumbent needs an id and a name.',
      );
    }

    final raw = json['events'];
    return LegislatorChronicle(
      id: incumbent['id'] as String,
      name: incumbent['name'] as String,
      party: PartyRef(name: incumbent['party'] as String? ?? '무소속'),
      summary: incumbent['summary'] as String? ?? '',
      portraitUrl: incumbent['portraitUrl'] as String?,
      events: List.unmodifiable(
        raw is List
            ? raw.map(ChronicleEvent.fromJson)
            : const <ChronicleEvent>[],
      ),
      source: SourceMetadata.fromJson(json['source'], field: 'legislator'),
    );
  }

  final String id;
  final String name;
  final PartyRef party;
  final String summary;
  final String? portraitUrl;
  final List<ChronicleEvent> events;
  final SourceMetadata source;
}

/// The seat has no member: the assembly's own member list names nobody for
/// this district. Carries that list as its source, since the absence is a
/// fact read from it, not an assumption.
class SeatVacancy {
  const SeatVacancy({required this.source});

  final SourceMetadata source;
}

/// The history tab's payload: the place, its elections, its representative.
///
/// Each part carries its own source because each comes from a different
/// publisher -- the district office, the election commission, the assembly --
/// and one badge for all three would misattribute two of them.
///
/// The place and its elections stand without a representative: a vacant seat
/// still has a past. [legislator] is null when there is nobody in the seat;
/// [vacancy] then says so with its source, or is null too when the feed could
/// not tell (nothing is said about the seat at all).
class HistoryRecord {
  const HistoryRecord({
    required this.district,
    required this.region,
    required this.elections,
    required this.legislator,
    this.vacancy,
  });

  factory HistoryRecord.fromJson(Map<String, Object?> json) {
    final districtJson = json['district'];
    if (districtJson is! Map<String, Object?>) {
      throw const MissingSourceException(
        field: 'district',
        reason: 'The district block is required.',
      );
    }

    final legislatorJson = json['legislator'];
    final vacancyJson =
        legislatorJson is Map && legislatorJson['vacant'] == true
        ? legislatorJson
        : null;
    return HistoryRecord(
      district: DistrictRef(
        id: districtJson['id'] as String? ?? '',
        displayName: districtJson['displayName'] as String? ?? '',
      ),
      region: RegionTimeline.fromJson(json['region']),
      elections: ElectionHistory.fromJson(json['elections']),
      legislator: legislatorJson == null || vacancyJson != null
          ? null
          : LegislatorChronicle.fromJson(legislatorJson),
      vacancy: vacancyJson == null
          ? null
          : SeatVacancy(
              source: SourceMetadata.fromJson(
                vacancyJson['source'],
                field: 'legislator',
              ),
            ),
    );
  }

  final DistrictRef district;
  final RegionTimeline region;
  final ElectionHistory elections;
  final LegislatorChronicle? legislator;
  final SeatVacancy? vacancy;

  /// The year the current incumbent first won this seat, if the election
  /// record shows it. Null for a seat nobody holds.
  int? get incumbentFirstWinYear => switch (legislator) {
    final legislator? => elections.firstWinYear(legislator.id),
    null => null,
  };
}
