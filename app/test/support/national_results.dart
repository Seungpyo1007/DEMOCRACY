/// A results payload the size of a real one: the 254 districts of the 22대
/// across 17 시도, a final count, no election pending, no polls -- the shape
/// `GET /districts/{id}/results` sends off election.
///
/// Fictional names and numbers. What is real is the size and the spread over
/// 시도, which is what the screen has to cope with.
Map<String, Object?> nationalResultsPayload() {
  const regions = {
    '서울': 48,
    '부산': 18,
    '대구': 12,
    '인천': 14,
    '광주': 8,
    '대전': 7,
    '울산': 6,
    '세종': 2,
    '경기': 60,
    '강원': 8,
    '충북': 8,
    '충남': 11,
    '전북': 10,
    '전남': 10,
    '경북': 13,
    '경남': 16,
    '제주': 3,
  };
  const source = {
    'sourceUrl': 'https://www.data.go.kr/data/15000900/openapi.do',
    'fetchedAt': '2026-09-27T03:00:00Z',
  };

  return {
    'electionName': '제22대 국회의원선거',
    'electionSchedule': null,
    'overallCountedShare': 100,
    'live': false,
    'districts': [
      for (final MapEntry(key: region, value: count) in regions.entries)
        for (var n = 1; n <= count; n++)
          {
            'districtId': nationalDistrictId(region, n),
            'districtName': '$region 가상$n구',
            'countedShare': 100,
            // Not in share order, as a wire in 기호 order would send it.
            'tallies': [
              {'name': '가상 후보 나', 'party': '나다당', 'share': 44.1},
              {'name': '가상 후보 다', 'party': '무소속', 'share': 4.7},
              {'name': '가상 후보 가', 'party': '가나당', 'share': 51.2},
            ],
            'source': source,
          },
    ],
    'historical': [
      {'year': 2016, 'share': 44.1},
      {'year': 2024, 'share': 51.2},
    ],
    'polls': <Object>[],
  };
}

String nationalDistrictId(String region, int n) => 'nec-$region-$n';
