import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';

/// Who a match is against.
///
/// At election time, the registered candidates. Between elections there are
/// none, so the match reads the sitting member's own pledges and bills
/// against the reader's interests -- and the screen says so, rather than
/// dressing one person up as a field of candidates.
enum MatchSubject {
  candidates,
  incumbent;

  static MatchSubject parse(Object? raw) =>
      raw == 'incumbent' ? incumbent : candidates;
}

/// What the reader asked the match to be about.
///
/// [interests] are the policy areas the score is broken down by, in the order
/// the reader was offered them; [context] is who is asking (자영업, 1인 가구),
/// read as background only.
class MatchQuery {
  const MatchQuery({this.interests = const [], this.context = const []});

  final List<String> interests;
  final List<String> context;
}

/// Raised when an on-device match has no interests to be about.
///
/// A match with no stated interest would have to invent its axes; the screen
/// asks the reader to pick some instead.
class MatchNeedsInterestsException implements Exception {
  const MatchNeedsInterestsException();
}

/// One axis of a match: a policy area and how well a candidate lines up on it.
///
/// Deliberately carries no [SourceMetadata]. A match score is produced by this
/// app's own model, not fetched from anywhere, and dressing it in an
/// attribution would borrow the authority the provenance rule exists to
/// establish. What is sourced is the pledge text underneath -- see
/// [MatchReason].
class MatchAxis {
  const MatchAxis({required this.label, required this.score});

  factory MatchAxis.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A match axis must be an object.');
    }

    final label = json['label'];
    final score = json['score'];
    if (label is! String || label.isEmpty || score is! num) {
      throw const FormatException('A match axis needs a label and a score.');
    }

    return MatchAxis(label: label, score: score.toDouble().clamp(0, 100));
  }

  final String label;

  /// 0..100.
  final double score;

  double get fraction => score / 100;

  String get display => score.round().toString();
}

/// A sentence of reasoning, and the pledge text it came from.
///
/// The link is required. A model's explanation of itself is not evidence; the
/// original wording is, and a reason the reader cannot trace back to it is
/// exactly the kind of unfalsifiable claim this product exists to avoid.
class MatchReason {
  const MatchReason({
    required this.text,
    required this.source,
    this.axis,
    this.cites,
  });

  factory MatchReason.fromJson(Object? json, {required String field}) {
    if (json is! Map) {
      throw MissingSourceException(
        field: field,
        reason: 'A reason must be an object.',
      );
    }

    final text = json['text'];
    if (text is! String || text.trim().isEmpty) {
      throw MissingSourceException(
        field: field,
        reason: 'A reason needs its text.',
      );
    }

    return MatchReason(
      text: text,
      source: SourceMetadata.fromJson(json['source'], field: field),
      axis: json['axis'] is String ? json['axis']! as String : null,
      cites: json['cites'] is String ? json['cites']! as String : null,
    );
  }

  final String text;
  final SourceMetadata source;

  /// The interest this reason is about, when the run gave one.
  final String? axis;

  /// The title of the pledge or bill it cites, as the input had it -- so the
  /// reader can see what the sentence is about before following the link.
  final String? cites;
}

/// How one candidate scored against the reader's stated interests.
class CandidateMatch {
  const CandidateMatch({
    required this.candidateId,
    required this.name,
    required this.party,
    required this.score,
    required this.headline,
    required this.axes,
    required this.reasons,
  });

  factory CandidateMatch.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A match must be an object.');
    }

    final id = json['candidateId'];
    final name = json['name'];
    final score = json['score'];
    if (id is! String || id.isEmpty || name is! String || score is! num) {
      throw const FormatException('A match needs a candidate, name and score.');
    }

    final rawAxes = json['axes'];
    final rawReasons = json['reasons'];

    return CandidateMatch(
      candidateId: id,
      name: name,
      party: PartyRef(name: json['party'] as String? ?? '무소속'),
      score: score.toDouble().clamp(0, 100),
      headline: json['headline'] as String? ?? '',
      axes: List.unmodifiable(
        rawAxes is List ? rawAxes.map(MatchAxis.fromJson) : const <MatchAxis>[],
      ),
      reasons: List.unmodifiable(
        rawReasons is List
            ? rawReasons.map(
                (reason) =>
                    MatchReason.fromJson(reason, field: 'match.$id.reason'),
              )
            : const <MatchReason>[],
      ),
    );
  }

  final String candidateId;
  final String name;
  final PartyRef party;
  final double score;

  /// One line saying what drove the number, e.g. how many pledges matched.
  final String headline;

  final List<MatchAxis> axes;
  final List<MatchReason> reasons;

  String get scoreDisplay => '${score.round()}점';
}

/// The whole result, plus what it would take to check it.
class MatchReport {
  const MatchReport({
    required this.matches,
    required this.comparedPledges,
    required this.weights,
    required this.generatedAt,
    this.subject = MatchSubject.candidates,
    this.comparedBills = 0,
    this.onDevice,
  });

  factory MatchReport.fromJson(Map<String, Object?> json) {
    final rawMatches = json['matches'];
    final matches = [
      if (rawMatches is List)
        for (final match in rawMatches) CandidateMatch.fromJson(match),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final generated = json['generatedAt'];

    return MatchReport(
      matches: List.unmodifiable(matches),
      comparedPledges: json['comparedPledges'] is int
          ? json['comparedPledges']! as int
          : 0,
      // Kept raw. The point of publishing the weights is that a reader can
      // check the arithmetic, and a parsed-and-reformatted copy is a second
      // artefact that can drift from what actually ran.
      weights: json['weights'] is Map
          ? Map<String, Object?>.unmodifiable(
              json['weights']! as Map<String, Object?>,
            )
          : const {},
      generatedAt: generated is String
          ? DateTime.tryParse(generated)?.toUtc()
          : null,
      subject: MatchSubject.parse(json['subject']),
      comparedBills: json['comparedBills'] is int
          ? json['comparedBills']! as int
          : 0,
    );
  }

  final List<CandidateMatch> matches;

  /// Candidates at election time; the sitting member between elections.
  final MatchSubject subject;

  /// How many bills the run compared, next to [comparedPledges].
  final int comparedBills;

  /// Set when this device's own model produced the result.
  final OnDeviceRun? onDevice;

  /// How many pledges the run compared, shown while it is still running.
  final int comparedPledges;

  /// The inputs and weights, verbatim, for the audit page.
  final Map<String, Object?> weights;

  final DateTime? generatedAt;

  CandidateMatch? get top => matches.isEmpty ? null : matches.first;

  List<CandidateMatch> get runnersUp =>
      matches.length <= 1 ? const [] : matches.sublist(1);
}

abstract interface class MatchRepository {
  Future<MatchReport> loadReport(
    String districtId, {
    MatchQuery query = const MatchQuery(),
  });

  /// The reasoning, delivered the way a model produces it.
  ///
  /// A stream rather than a string because the real one arrives token by
  /// token, and a screen built against a completed string would have to be
  /// rewritten to show it arriving.
  Stream<String> streamReasoning(String districtId, String candidateId);
}

/// What a run in progress has produced so far.
///
/// [verified] holds only reasons whose cited pledge or bill exists in the
/// input -- a reason is shown while the model is still writing only once it
/// has passed the same check the final result does.
class MatchProgress {
  const MatchProgress({required this.verified, required this.characters});

  final List<MatchReason> verified;

  /// How much the model has written, for a platform whose snapshots do not
  /// parse until the end.
  final int characters;
}

/// A repository whose runs report progress while they go (the on-device one).
abstract interface class MatchProgressSource {
  Stream<MatchProgress> get progress;
}
