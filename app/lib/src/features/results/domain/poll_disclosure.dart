import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/kst.dart';

/// Raised when a poll is published without an item 제108조제5항 requires.
///
/// A plain exception rather than an assert, for the same reason as
/// [MissingSourceException]: assertions are stripped from release builds, and
/// an undisclosed poll reaching a screen in production is exactly the case
/// that has to fail.
///
/// It reports every missing item at once. A parser that stops at the first
/// omission makes a caller fix nine payloads to learn about nine fields.
class MissingDisclosureException implements Exception {
  const MissingDisclosureException({
    required this.pollLabel,
    required this.missing,
  });

  final String pollLabel;

  /// The Korean names of the required items, so the failure reads as the law
  /// reads.
  final List<String> missing;

  @override
  String toString() =>
      'MissingDisclosureException on "$pollLabel": ${missing.join(', ')} 누락';
}

/// The items 공직선거법 제108조제5항 requires to accompany a published poll.
///
/// Every field is non-nullable and there is no constructor that omits one, so
/// a poll carrying a disclosure carries all of it by construction. That is the
/// same move [SourceMetadata] makes for provenance: the incomplete case is not
/// a state the type can be in.
///
/// [nesdcRegistration] is required for an in-app survey too. 제108조제5항 does
/// not exempt one, and since a client cannot register a survey with the
/// 중앙선거여론조사심의위원회, the effect is that a series the BFF cannot
/// evidence simply does not render. That is the correct legal outcome, and it
/// falls out of the type rather than out of a reviewer remembering.
class PollDisclosure {
  PollDisclosure({
    required this.client,
    required this.pollster,
    required this.fieldStart,
    required this.fieldEnd,
    required this.sampleSize,
    required this.samplingMethod,
    required this.surveyMethod,
    required this.marginOfError,
    required this.confidenceLevel,
    required this.responseRate,
    required this.questionnaire,
    required this.nesdcRegistration,
    required this.source,
  });

  factory PollDisclosure.fromJson(Object? json, {required String pollLabel}) {
    final missing = <String>[];

    if (json is! Map) {
      throw MissingDisclosureException(
        pollLabel: pollLabel,
        missing: const ['표기사항 전체'],
      );
    }

    String text(String key, String korean) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        missing.add(korean);
        return '';
      }
      return value;
    }

    // Rates are percentages, so a value outside 0..100 is not a rounding
    // question -- it is a payload that did not mean a percentage.
    double rate(String key, String korean, {double max = 100}) {
      final value = json[key];
      if (value is! num || value < 0 || value > max) {
        missing.add(korean);
        return 0;
      }
      return value.toDouble();
    }

    KstInstant? moment(String key, String korean) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        missing.add(korean);
        return null;
      }
      try {
        return KstInstant.parse(value, field: key);
      } on ArgumentError {
        missing.add(korean);
        return null;
      }
    }

    Uri? link(String key, String korean) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        missing.add(korean);
        return null;
      }
      final parsed = Uri.tryParse(value);
      // The same rule provenance uses: a relative path or a file:// URL is not
      // something a reader can open to check the claim.
      if (parsed == null ||
          !parsed.isAbsolute ||
          parsed.host.isEmpty ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        missing.add(korean);
        return null;
      }
      return parsed;
    }

    final client = text('client', '조사의뢰자');
    final pollster = text('pollster', '조사기관');
    final start = moment('fieldStart', '조사일시');
    final end = moment('fieldEnd', '조사일시');
    final sample = json['sampleSize'];
    if (sample is! int || sample <= 0) {
      missing.add('표본크기');
    }
    final samplingMethod = text('samplingMethod', '피조사자 선정방법');
    final surveyMethod = text('surveyMethod', '조사방법');
    final marginOfError = rate('marginOfError', '표본오차', max: 50);
    final confidenceLevel = rate('confidenceLevel', '신뢰수준');
    final responseRate = rate('responseRate', '응답률');
    final questionnaire = link('questionnaire', '질문내용');
    final registration = link('nesdcRegistration', '심의위 등록');

    if (missing.isNotEmpty) {
      throw MissingDisclosureException(
        pollLabel: pollLabel,
        // A repeated item -- both ends of 조사일시 -- should be said once.
        missing: missing.toSet().toList(),
      );
    }

    return PollDisclosure(
      client: client,
      pollster: pollster,
      fieldStart: start!,
      fieldEnd: end!,
      sampleSize: sample! as int,
      samplingMethod: samplingMethod,
      surveyMethod: surveyMethod,
      marginOfError: marginOfError,
      confidenceLevel: confidenceLevel,
      responseRate: responseRate,
      questionnaire: questionnaire!,
      nesdcRegistration: registration!,
      source: SourceMetadata.fromJson(json['source'], field: 'poll.$pollLabel'),
    );
  }

  /// 조사의뢰자.
  final String client;

  /// 조사기관.
  final String pollster;

  /// 조사일시.
  final KstInstant fieldStart;
  final KstInstant fieldEnd;

  /// 표본크기.
  final int sampleSize;

  /// 피조사자 선정방법.
  final String samplingMethod;

  /// 조사방법.
  final String surveyMethod;

  /// 표본오차, in percentage points.
  final double marginOfError;

  /// 신뢰수준, as a percentage.
  final double confidenceLevel;

  /// 응답률.
  final double responseRate;

  /// 질문내용 원문.
  final Uri questionnaire;

  /// The 중앙선거여론조사심의위원회 registration page.
  final Uri nesdcRegistration;

  final SourceMetadata source;

  /// What has to sit next to the figure itself.
  ///
  /// The law requires the disclosure to accompany the published result, not to
  /// be reachable from it -- a sheet the reader never opens is not an
  /// accompaniment. The sheet carries the rest.
  String get inlineNotice =>
      '$pollster · ${fieldStart.dayLabel}~${fieldEnd.dayLabel} · '
      '표본 $sampleSize명 · 오차 ±${marginOfError.toStringAsFixed(1)}%p '
      '(신뢰수준 ${confidenceLevel.round()}%) · 응답률 '
      '${responseRate.toStringAsFixed(1)}%';
}
