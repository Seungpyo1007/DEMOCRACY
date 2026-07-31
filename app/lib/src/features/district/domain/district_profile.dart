import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';

/// A party as the product is allowed to show it: a name only.
///
/// There is no colour field by design. The neutrality rules forbid party
/// colour anywhere in the UI, and a colour that does not exist in the model
/// cannot leak into a widget later.
class PartyRef {
  const PartyRef({required this.name});

  final String name;
}

/// One measured figure about a person, ready to render with its badge.
class DistrictStat {
  const DistrictStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  factory DistrictStat.fromJson(Map<String, Object?> json) {
    final label = json['label'];
    if (label is! String || label.isEmpty) {
      throw MissingSourceException(
        field: 'stat.label',
        reason: 'A stat needs a label.',
      );
    }

    return DistrictStat(
      label: label,
      value: SourcedValue<num>.fromJson(json['value'], field: 'stat.$label'),
      unit: json['unit'] as String? ?? '',
    );
  }

  final String label;
  final SourcedValue<num> value;
  final String unit;

  /// Descriptive only. The copy rules bar evaluative wording, so this renders
  /// the figure and nothing more.
  String get display => '${value.value}$unit';
}

/// Someone holding or seeking the seat. One shape for both so that incumbents
/// and challengers cannot drift into different card specs.
class Politician {
  const Politician({
    required this.id,
    required this.name,
    required this.party,
    required this.summary,
    required this.stats,
    this.portraitUrl,
  });

  factory Politician.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) {
      throw MissingSourceException(
        field: 'politician',
        reason: 'id and name are required.',
      );
    }

    final rawStats = json['stats'];
    return Politician(
      id: id,
      name: name,
      party: PartyRef(name: json['party'] as String? ?? '무소속'),
      summary: json['summary'] as String? ?? '',
      portraitUrl: json['portraitUrl'] as String?,
      stats: [
        if (rawStats is List)
          for (final stat in rawStats)
            DistrictStat.fromJson(stat as Map<String, Object?>),
      ],
    );
  }

  final String id;
  final String name;
  final PartyRef party;
  final String summary;
  final List<DistrictStat> stats;
  final String? portraitUrl;
}

/// The district home payload.
class DistrictProfile {
  const DistrictProfile({
    required this.district,
    required this.incumbent,
    required this.candidates,
    required this.source,
  });

  factory DistrictProfile.fromJson(Map<String, Object?> json) {
    final districtJson = json['district'];
    if (districtJson is! Map<String, Object?>) {
      throw MissingSourceException(
        field: 'district',
        reason: 'The district block is required.',
      );
    }

    final rawCandidates = json['candidates'];
    final candidates = <Politician>[
      if (rawCandidates is List)
        for (final candidate in rawCandidates)
          Politician.fromJson(candidate as Map<String, Object?>),
    ];

    return DistrictProfile(
      district: DistrictRef(
        id: districtJson['id'] as String? ?? '',
        displayName: districtJson['displayName'] as String? ?? '',
      ),
      incumbent: Politician.fromJson(
        json['incumbent'] as Map<String, Object?>? ?? const {},
      ),
      candidates: sortedByName(candidates),
      source: SourceMetadata.fromJson(json['source'], field: 'district'),
    );
  }

  /// Candidates are ordered by name, never by ballot number, and the ordering
  /// lives here rather than in a widget so every surface inherits it.
  static List<Politician> sortedByName(List<Politician> candidates) {
    final ordered = [...candidates]..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(ordered);
  }

  static const sortLabel = '가나다순';

  final DistrictRef district;
  final Politician incumbent;
  final List<Politician> candidates;
  final SourceMetadata source;
}
