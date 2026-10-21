import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/election_schedule.dart';

/// A value the law may forbid publishing right now.
///
/// Sealed, and with no getter for the payload on the base type. A caller
/// cannot reach the value without writing a `switch` that has a [Withheld]
/// arm, and a `switch` over a sealed hierarchy that misses an arm does not
/// compile. That is the whole design: a screen cannot draw embargoed figures
/// by forgetting an `if`, because there is no `if` to forget.
///
/// This is the same move [MissingSourceException] makes one layer down --
/// make the wrong thing unrepresentable rather than guarded.
sealed class Restricted<T> {
  const Restricted();
}

final class Published<T> extends Restricted<T> {
  const Published(this.value);

  final T value;
}

final class Withheld<T> extends Restricted<T> {
  const Withheld({
    required this.article,
    required this.notice,
    required this.until,
  });

  /// The provision being complied with. Shown to the reader, because a blank
  /// panel that does not say why reads as a bug.
  final String article;

  final String notice;

  /// When the restriction lifts.
  final KstInstant until;
}

/// The counting half of a results view, restricted as one unit.
///
/// The share, the districts and the LIVE flag are withheld together because
/// they are the same disclosure: publishing the district tallies while hiding
/// the headline number would comply with nothing.
class CountView {
  const CountView({
    required this.overallCountedShare,
    required this.districts,
    required this.live,
    this.overallSource,
  });

  final double overallCountedShare;
  final SourceMetadata? overallSource;
  final List<DistrictCount> districts;
  final bool live;

  DistrictCount? byId(String id) {
    for (final district in districts) {
      if (district.districtId == id) {
        return district;
      }
    }
    return null;
  }
}

/// Turns a parsed payload into something renderable, or refuses to.
///
/// This is the only producer of [ElectionResults] -- its constructor is
/// private to its own library -- so there is no path from the repository to a
/// screen that skips this check.
abstract final class PublicationGate {
  static ElectionResults apply(
    RawElectionResults raw, {
    required KstInstant now,
  }) {
    final schedule = raw.schedule;

    final counts = CountView(
      overallCountedShare: raw.overallCountedShare,
      overallSource: raw.overallSource,
      districts: raw.districts,
      live: raw.live,
    );

    if (schedule == null) {
      return ElectionResults.published(
        electionName: raw.electionName,
        counts: counts,
        historical: raw.historical,
        polls: raw.polls,
      );
    }

    return ElectionResults.gated(
      electionName: raw.electionName,
      // 역대 결과 is a past election's published outcome. Neither provision
      // reaches it, so it is not wrapped -- withholding it would be the app
      // inventing a restriction, which is its own kind of distortion.
      historical: raw.historical,
      counts: schedule.blocksCountAt(now)
          ? Withheld(
              article: '공직선거법 제167조제2항',
              notice:
                  '투표마감시각 전에는 개표 결과를 표시할 수 없습니다. '
                  '${schedule.pollsClose.stampLabel}에 공개됩니다.',
              until: schedule.pollsClose,
            )
          : Published(counts),
      polls: schedule.blocksPollsAt(now)
          ? Withheld(
              article: '공직선거법 제108조제1항',
              notice:
                  '선거일 전 6일부터 투표마감시각까지는 여론조사 결과를 표시할 수 없습니다. '
                  '${schedule.pollsClose.stampLabel}에 공개됩니다.',
              until: schedule.pollsClose,
            )
          : Published(raw.polls),
    );
  }

  /// The gate when the app has no server time yet.
  ///
  /// With no election pending there is nothing to withhold. Otherwise the
  /// device clock cannot be trusted to place "now" either side of a deadline,
  /// so counts and polls both wait until a fresh response gives server time.
  static ElectionResults applyWithoutServerTime(RawElectionResults raw) {
    final schedule = raw.schedule;
    if (schedule == null) {
      return ElectionResults.published(
        electionName: raw.electionName,
        counts: CountView(
          overallCountedShare: raw.overallCountedShare,
          overallSource: raw.overallSource,
          districts: raw.districts,
          live: raw.live,
        ),
        historical: raw.historical,
        polls: raw.polls,
      );
    }
    const notice = '서버 시각을 확인한 뒤에 표시합니다. 연결되면 바로 보입니다.';
    return ElectionResults.gated(
      electionName: raw.electionName,
      historical: raw.historical,
      counts: Withheld(
        article: '공직선거법 제167조제2항',
        notice: notice,
        until: schedule.pollsClose,
      ),
      polls: Withheld(
        article: '공직선거법 제108조제1항',
        notice: notice,
        until: schedule.pollsClose,
      ),
    );
  }

  /// The next moment a verdict changes, or null if none is ahead.
  ///
  /// The gate runs per emission, so a stream that goes quiet at 17:59 would
  /// keep showing a count past closing -- and, worse in the other direction, a
  /// stream that last spoke on the seventh day out would keep showing polls
  /// into the blackout. The provider arms a timer on this.
  static KstInstant? nextBoundary(
    ElectionSchedule? schedule, {
    required KstInstant now,
  }) {
    if (schedule == null) {
      return null;
    }
    for (final boundary in [schedule.pollBlackoutStart, schedule.pollsClose]) {
      if (now.isBefore(boundary)) {
        return boundary;
      }
    }
    return null;
  }
}
