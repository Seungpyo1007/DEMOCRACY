import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/domain/publication_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _results() =>
    jsonDecode(
          File(
            'assets/fixtures/results_fixture-seoul-mapo-b.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

CountView _counts(Map<String, Object?> json) {
  final view = PublicationGate.apply(
    RawElectionResults.fromJson(json),
    now: KstInstant.seoul(2026, 7, 30, 18),
  );
  return (view.counts as Published<CountView>).value;
}

void main() {
  test('the national share keeps the source the server gives it', () {
    final counts = _counts(_results());

    expect(
      counts.overallSource?.sourceUrl,
      Uri.parse('https://www.data.go.kr/data/15000900/openapi.do'),
    );
  });

  test('an older payload without one still parses', () {
    final counts = _counts(_results()..remove('overallSource'));

    expect(counts.overallSource, isNull);
    expect(counts.districts, isNotEmpty);
  });
}
