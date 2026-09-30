import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/kst.dart';

/// Raised when a results payload never said whether an election is pending.
///
/// A plain exception rather than a default, and rather than an assert, for the
/// same reason as [MissingSourceException]: assertions are stripped from
/// release builds, and the case that has to fail is a screen deciding on its
/// own that no embargo applies.
class MissingScheduleException implements Exception {
  const MissingScheduleException(this.reason);

  final String reason;

  @override
  String toString() => 'MissingScheduleException: $reason';
}

/// The two deadlines 공직선거법 attaches to an election, and where they came
/// from.
///
/// These are payload fields rather than client constants, and that is not a
/// close call. 투표마감시각 is 18:00 for a general election but 20:00 for a
/// 재·보궐선거, and the NEC can extend closing at an individual 투표소. A
/// constant compiled into a binary would publish counts during a lawful
/// extension, and shipping a correction means racing an app-store review. The
/// date also carries [source] because it is a figure with legal consequences,
/// and this app already refuses figures that cannot say where they came from.
class ElectionSchedule {
  ElectionSchedule({
    required this.electionName,
    required this.pollsClose,
    required this.source,
  });

  /// Reads the schedule out of a results payload.
  ///
  /// Silence and an explicit "no election" are different answers. A missing
  /// key means the payload never addressed the question, and deciding for it
  /// is exactly the guess that publishes embargoed figures -- so absence
  /// throws. Saying `null` is how a server states there is no election
  /// pending, and that statement is honoured.
  static ElectionSchedule? read(Map<String, Object?> json) {
    if (!json.containsKey('electionSchedule')) {
      throw const MissingScheduleException(
        'The payload carries no "electionSchedule" key. It has to say so '
        'explicitly, with null, when no election is pending.',
      );
    }

    final raw = json['electionSchedule'];
    if (raw == null) {
      return null;
    }
    if (raw is! Map<String, Object?>) {
      throw const MissingScheduleException(
        '"electionSchedule" must be an object or null.',
      );
    }

    final close = raw['pollsClose'];
    if (close is! String || close.isEmpty) {
      throw const MissingScheduleException(
        'A schedule needs "pollsClose", the authoritative closing time '
        'including any NEC extension.',
      );
    }

    return ElectionSchedule(
      electionName: raw['electionName'] as String? ?? '',
      pollsClose: KstInstant.parse(close, field: 'pollsClose'),
      source: SourceMetadata.fromJson(raw['source'], field: 'electionSchedule'),
    );
  }

  final String electionName;

  /// 투표마감시각, as announced -- not a constant derived from the election
  /// type.
  final KstInstant pollsClose;

  final SourceMetadata source;

  /// 제108조제1항 -- the ban runs from 00:00 KST on the sixth day before the
  /// election day. Derived from [pollsClose] rather than stored separately so
  /// the two can never disagree about which day the election is.
  KstInstant get pollBlackoutStart => pollsClose.minusDays(6).startOfDay;

  /// 제108조제1항: 여론조사 경위와 결과는 이 기간에 공표할 수 없다.
  bool blocksPollsAt(KstInstant now) =>
      now.isAtOrAfter(pollBlackoutStart) && now.isBefore(pollsClose);

  /// 제167조제2항: 개표 결과와 출구조사는 투표마감시각 전에 공표할 수 없다.
  ///
  /// Note this is not the same window as [blocksPollsAt]: a count is embargoed
  /// from any time before closing, not only from the sixth day.
  bool blocksCountAt(KstInstant now) => now.isBefore(pollsClose);
}
