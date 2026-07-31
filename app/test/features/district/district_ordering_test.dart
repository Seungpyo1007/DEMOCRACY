import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Candidates must appear in name order, never in ballot order, and every one
/// of them must carry the same information in the same shape.
void main() {
  Map<String, Object?> candidateJson(String name, {String party = '무소속'}) {
    return {
      'id': 'fixture-$name',
      'name': name,
      'party': party,
      'stats': <Object?>[],
    };
  }

  Map<String, Object?> profileJson(List<String> names) {
    return {
      'district': {'id': 'fixture-a', 'displayName': '가상 지역구'},
      'source': {
        'sourceUrl': 'https://open.assembly.go.kr/fixture',
        'fetchedAt': '2026-07-30T09:00:00Z',
      },
      'incumbent': candidateJson('가상 의원'),
      'candidates': [for (final name in names) candidateJson(name)],
    };
  }

  test('candidates come back in name order whatever order they arrived in', () {
    final profile = DistrictProfile.fromJson(
      profileJson(['다후보', '가후보', '나후보']),
    );

    expect(profile.candidates.map((candidate) => candidate.name), [
      '가후보',
      '나후보',
      '다후보',
    ]);
  });

  test('the ordering in force is published for the interface to show', () {
    expect(DistrictProfile.sortLabel, '가나다순');
  });

  test('every candidate exposes the same fields', () {
    final profile = DistrictProfile.fromJson(profileJson(['가후보', '나후보']));

    for (final candidate in profile.candidates) {
      expect(candidate.id, isNotEmpty);
      expect(candidate.name, isNotEmpty);
      expect(candidate.party.name, isNotEmpty);
      expect(candidate.stats, isNotNull);
    }
  });

  test('a party is a name only, with no colour to leak into the interface', () {
    const party = PartyRef(name: '가나당');

    expect(party.name, '가나당');
    expect(
      party.toString(),
      isNot(contains('Color')),
      reason: 'PartyRef must not gain a colour field.',
    );
  });
}
