import 'package:democracy/src/core/provenance/source_metadata.dart';

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

/// A poll series.
///
/// [accredited] is the whole point of the type. An in-app poll and a
/// registered pollster's are not the same kind of number, and the guide
/// requires the difference to be visible at all times -- so it is a field
/// rather than a styling choice made at the call site.
class PollSeries {
  const PollSeries({
    required this.label,
    required this.accredited,
    required this.points,
  });

  factory PollSeries.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A poll series must be an object.');
    }

    final label = json['label'];
    if (label is! String || label.isEmpty) {
      throw const FormatException('A poll series needs a label.');
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
    );
  }

  final String label;

  /// True for 갤럽 and 리얼미터; false for anything this app collected.
  final bool accredited;

  final List<HistoricalPoint> points;

  String get caption => accredited ? '$label · 공인 조사' : '$label · 공인 조사 아님';
}

/// The whole election view: the map, the selected district, and the two
/// comparisons the guide puts behind a segmented control.
class ElectionResults {
  const ElectionResults({
    required this.electionName,
    required this.overallCountedShare,
    required this.districts,
    required this.historical,
    required this.polls,
    required this.live,
  });

  factory ElectionResults.fromJson(Map<String, Object?> json) {
    final rawDistricts = json['districts'];
    final rawHistorical = json['historical'];
    final rawPolls = json['polls'];

    return ElectionResults(
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

  String get header =>
      '$electionName · 개표율 ${overallCountedShare.toStringAsFixed(1)}%';

  DistrictCount? byId(String id) {
    for (final district in districts) {
      if (district.districtId == id) {
        return district;
      }
    }
    return null;
  }
}

abstract interface class ResultsRepository {
  /// A stream because on election day this is SSE, and off it a slow poll.
  /// The screen should not know which it is getting.
  Stream<ElectionResults> watch(String districtId);
}
