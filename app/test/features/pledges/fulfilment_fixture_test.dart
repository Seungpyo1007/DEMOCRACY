import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('assets/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;

void main() {
  // The home card and the tracker show the same figure. Live, the server
  // derives both from one board; offline they come from two fixtures, which
  // drifted apart once (58% on home, 38% on the tracker).
  test('home 공약 이행 matches the pledge board it summarises', () {
    final profile = DistrictProfile.fromJson(
      _fixture('district_fixture-seoul-mapo-b'),
    );
    final board = PledgeBoard.fromJson(
      _fixture('pledges_fixture-seoul-mapo-b'),
    );

    final stat = profile.incumbent!.stats.singleWhere(
      (s) => s.label == '공약 이행',
    );

    expect('${stat.value.value}%', board.fulfilmentDisplay);
    expect(stat.value.source.sourceUrl, board.source.sourceUrl);
  });
}
