import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/results/domain/election_schedule.dart';
import 'package:democracy/src/features/results/domain/poll_disclosure.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';

/// One candidate's share in a district.
///
/// Carries no party colour and no way to supply one, for the same reason
/// [PartyRef] does not: the moment a bar can be tinted by party, the screen
/// starts arguing.
class CandidateTally {
  const CandidateTally({
    required this.name,
    required this.party,
    required this.share,
  });

  factory CandidateTally.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A tally must be an object.');
    }

    final name = json['name'];
    final share = json['share'];
    if (name is! String || name.isEmpty || share is! num) {
      throw const FormatException('A tally needs a name and a share.');
    }

    return CandidateTally(
      name: name,
      party: json['party'] as String? ?? '무소속',
      share: share.toDouble().clamp(0, 100),
    );
  }

  final String name;
  final String party;

  /// Percent of counted votes.
  final double share;

  double get fraction => share / 100;

  String get display => '${share.toStringAsFixed(1)}%';
}

/// A district's count so far.
class DistrictCount {
  const DistrictCount({
    required this.districtId,
    required this.districtName,
    required this.countedShare,
    required this.tallies,
    required this.source,
  });

  factory DistrictCount.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'districtCount',
        reason: 'A count must be an object.',
      );
    }

    final id = json['districtId'];
    final name = json['districtName'];
    final counted = json['countedShare'];
    if (id is! String || id.isEmpty || name is! String || counted is! num) {
      throw const MissingSourceException(
        field: 'districtCount',
        reason: 'A count needs a district and a counted share.',
      );
    }

    final rawTallies = json['tallies'];
    return DistrictCount(
      districtId: id,
      districtName: name,
      countedShare: counted.toDouble().clamp(0, 100),
      tallies: List.unmodifiable(
        rawTallies is List
            ? (rawTallies.map(CandidateTally.fromJson).toList()
                ..sort((a, b) => b.share.compareTo(a.share)))
            : const <CandidateTally>[],
      ),
      source: SourceMetadata.fromJson(
        json['source'],
        field: 'districtCount.$id',
      ),
    );
  }

  final String districtId;
  final String districtName;

  /// 0..100. Also the only thing that decides how dark the district is drawn.
  final double countedShare;

  final List<CandidateTally> tallies;
  final SourceMetadata source;

  double get countedFraction => countedShare / 100;

  String get countedDisplay => '개표 ${countedShare.round()}%';
}

/// One year's outcome, for the historical line.
class HistoricalPoint {
  const HistoricalPoint({required this.year, required this.share});

  factory HistoricalPoint.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A historical point must be an object.');
    }

    final year = json['year'];
    final share = json['share'];
    if (year is! int || share is! num) {
      throw const FormatException('A historical point needs a year and share.');
    }

    return HistoricalPoint(year: year, share: share.toDouble());
  }

  final int year;
  final double share;
}

/// A poll series, with the disclosure the law makes inseparable from it.
///
/// [accredited] draws the distinction the guide asks to be visible at all
/// times, but it is no longer the whole disclosure: 제108조제5항 requires the
/// nine items in [PollDisclosure] to accompany any published result, and this
/// was the one political figure in the app that rendered without provenance of
/// any kind. It now fails to parse rather than fails to disclose.
class PollSeries {
  const PollSeries({
    required this.label,
    required this.accredited,
    required this.points,
    required this.disclosure,
  });

  factory PollSeries.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingDisclosureException(
        pollLabel: '(무명)',
        missing: ['조사 자체'],
      );
    }

    final label = json['label'];
    if (label is! String || label.isEmpty) {
      throw const MissingDisclosureException(
        pollLabel: '(무명)',
        missing: ['조사기관'],
      );
    }

    final raw = json['points'];
    return PollSeries(
      label: label,
      accredited: json['accredited'] as bool? ?? false,
      points: List.unmodifiable(
        raw is List
            ? raw.map(HistoricalPoint.fromJson)
            : const <HistoricalPoint>[],
      ),
      disclosure: PollDisclosure.fromJson(json['disclosure'], pollLabel: label),
    );
  }

  final String label;

  /// True for a pollster registered with the 중앙선거여론조사심의위원회.
  /// It changes how the series is drawn, not whether it must disclose.
  final bool accredited;

  final List<HistoricalPoint> points;
  final PollDisclosure disclosure;

  String get caption => accredited ? '$label · 공인 조사' : '$label · 공인 조사 아님';
}

/// The payload as it arrived, before any embargo is applied.
///
/// This is what a repository yields. It is a separate type from
/// [ElectionResults] so that "parsed" and "publishable" cannot be confused:
/// the figures here are ungated, and the only way to get a publishable view is
/// through [PublicationGate].
class RawElectionResults {
  const RawElectionResults({
    required this.electionName,
    required this.overallCountedShare,
    required this.districts,
    required this.historical,
    required this.polls,
    required this.live,
    required this.schedule,
  });

  factory RawElectionResults.fromJson(Map<String, Object?> json) {
    final rawDistricts = json['districts'];
    final rawHistorical = json['historical'];
    final rawPolls = json['polls'];

    return RawElectionResults(
      schedule: ElectionSchedule.read(json),
      electionName: json['electionName'] as String? ?? '',
      overallCountedShare: json['overallCountedShare'] is num
          ? (json['overallCountedShare']! as num).toDouble()
          : 0,
      districts: List.unmodifiable(
        rawDistricts is List
            ? rawDistricts.map(DistrictCount.fromJson)
            : const <DistrictCount>[],
      ),
      historical: List.unmodifiable(
        rawHistorical is List
            ? rawHistorical.map(HistoricalPoint.fromJson)
            : const <HistoricalPoint>[],
      ),
      polls: List.unmodifiable(
        rawPolls is List
            ? rawPolls.map(PollSeries.fromJson)
            : const <PollSeries>[],
      ),
      live: json['live'] as bool? ?? false,
    );
  }

  final String electionName;
  final double overallCountedShare;
  final List<DistrictCount> districts;
  final List<HistoricalPoint> historical;
  final List<PollSeries> polls;

  /// Whether counting is running now. Drives the LIVE dot and nothing else --
  /// the numbers say the same thing either way.
  final bool live;

  /// Null only when the payload said so explicitly. A payload that stayed
  /// silent never reaches here -- [ElectionSchedule.read] throws.
  final ElectionSchedule? schedule;
}

/// What a screen is allowed to draw.
///
/// The counting figures and the polls are wrapped in [Restricted] because
/// 공직선거법 forbids publishing them at certain times. The constructors are
/// private to this library so [PublicationGate] is the only thing that can
/// make one -- there is no route from a repository to a screen that skips the
/// check.
class ElectionResults {
  const ElectionResults._({
    required this.electionName,
    required this.counts,
    required this.historical,
    required this.polls,
  });

  /// The shape when no election is pending and nothing is embargoed.
  factory ElectionResults.published({
    required String electionName,
    required CountView counts,
    required List<HistoricalPoint> historical,
    required List<PollSeries> polls,
  }) => ElectionResults._(
    electionName: electionName,
    counts: Published(counts),
    historical: historical,
    polls: Published(polls),
  );

  factory ElectionResults.gated({
    required String electionName,
    required Restricted<CountView> counts,
    required List<HistoricalPoint> historical,
    required Restricted<List<PollSeries>> polls,
  }) => ElectionResults._(
    electionName: electionName,
    counts: counts,
    historical: historical,
    polls: polls,
  );

  final String electionName;
  final Restricted<CountView> counts;

  /// Not restricted. A past election's published outcome is not covered by
  /// either provision, and hiding it would be the app inventing a rule.
  final List<HistoricalPoint> historical;

  final Restricted<List<PollSeries>> polls;

  /// The header can only state a counted share once counting may be shown.
  String get header => switch (counts) {
    Published(:final value) =>
      '$electionName · 개표율 ${value.overallCountedShare.toStringAsFixed(1)}%',
    Withheld() => electionName,
  };
}

abstract interface class ResultsRepository {
  /// A stream because on election day this is SSE, and off it a slow poll.
  /// The screen should not know which it is getting.
  ///
  /// It yields the ungated payload: withholding is a decision about *now*, and
  /// a repository that made it at fetch time would be answering a question
  /// whose answer changes while the value sits in a stream.
  Stream<RawElectionResults> watch(String districtId);
}
