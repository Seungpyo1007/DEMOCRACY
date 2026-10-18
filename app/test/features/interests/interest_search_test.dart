import 'package:democracy/src/features/interests/domain/hangul.dart';
import 'package:democracy/src/features/interests/domain/interest_catalog.dart';
import 'package:democracy/src/features/interests/domain/interest_taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _labels(String query) => [
  for (final interest in searchInterests(query)) interest.label,
];

void main() {
  group('Hangul decomposition', () {
    test('takes a syllable apart by the Unicode formula', () {
      final ga = decompose('가'.runes.single)!;
      expect((ga.cho, ga.jung, ga.jong), (0, 0, 0));

      final hih = decompose('힣'.runes.single)!;
      expect((hih.initial, hih.finalConsonant), ('ㅎ', 'ㅎ'));

      final tong = decompose('통'.runes.single)!;
      expect((tong.initial, tong.finalConsonant), ('ㅌ', 'ㅇ'));
    });

    test('leaves anything that is not a syllable alone', () {
      expect(decompose('a'.runes.single), isNull);
      expect(decompose('ㄱ'.runes.single), isNull);
      expect(initialsOf('GTX 지하철'), 'GTX ㅈㅎㅊ');
    });

    test('initial-consonant queries match by 초성', () {
      expect(hangulContains('교통', 'ㄱㅌ'), isTrue);
      expect(hangulContains('지하철·광역철도', 'ㅈㅎㅊ'), isTrue);
      expect(hangulContains('지하철·광역철도', 'ㄱㅇㅊㄷ'), isTrue);
      expect(hangulContains('교통', 'ㄱㄷ'), isFalse);
      // Mixed: a whole syllable, then an initial.
      expect(hangulContains('교통', '교ㅌ'), isTrue);
      expect(hangulContains('교통', '고ㅌ'), isFalse);
    });

    test('a last syllable still being typed matches the finished one', () {
      // ㄱㅛㅌㅗ → 교토, one keystroke short of 교통.
      expect(hangulContains('교통', '교토'), isTrue);
      // ㅂㅓㅅ → 벗, the keyboard holding 스's ㅅ as a final.
      expect(hangulContains('버스', '벗'), isTrue);
      // Only the last character gets that latitude.
      expect(hangulContains('교통비', '교토비'), isFalse);
      expect(hangulContains('버스', '벚'), isFalse);
    });

    test('ignores spaces, the middle dot and Latin case', () {
      expect(hangulContains('지하철·광역철도', '철 광역'), isTrue);
      expect(hangulContains('GTX', 'gtx'), isTrue);
      expect(hangulIndexOf('교통비·환승', '교통'), 0);
      expect(hangulIndexOf('교통안전·스쿨존', '안전'), 2);
    });
  });

  group('searchInterests', () {
    test('초성 finds the 분야 first, then what is under it', () {
      final results = _labels('ㄱㅌ');
      expect(results.first, '교통');
      expect(results, containsAll(['교통비·환승', '교통안전·스쿨존']));
    });

    test('a synonym finds the topic it belongs to', () {
      expect(_labels('GTX'), ['지하철·광역철도']);
      expect(_labels('전세 사기'), contains('전월세'));
      expect(_labels('늘봄'), ['돌봄교실·방과후']);
      expect(_labels('유기견'), ['동물복지·유기동물']);
    });

    test('a label hit outranks a keyword hit', () {
      final results = _labels('주차');
      expect(results.first, '도로·주차');
    });

    test('searching a 분야 name lists the 분야 and every topic in it', () {
      final results = searchInterests('반려동물');
      expect(results.first.isWholeArea, isTrue);
      expect(
        results.map((i) => i.id),
        containsAll(['pets', 'pets.facility', 'pets.welfare', 'pets.cost']),
      );
    });

    test('nothing for an empty query or one that matches nothing', () {
      expect(searchInterests(''), isEmpty);
      expect(searchInterests('  '), isEmpty);
      expect(searchInterests('우주여행'), isEmpty);
    });
  });

  group('the taxonomy', () {
    test('is about twenty 분야 and a hundred topics', () {
      final topics = interestAreas.expand((a) => a.topics).length;
      expect(interestAreas.length, inInclusiveRange(18, 24));
      expect(topics, inInclusiveRange(90, 120));
    });

    test('every id and every label is unique', () {
      // The match names its axes by label and checks the answer against
      // them, so two interests sharing a label would be one axis.
      final ids = InterestCatalog.all.map((i) => i.id).toList();
      final labels = InterestCatalog.all.map((i) => i.label).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('every topic id sits under its 분야 id and has keywords', () {
      for (final area in interestAreas) {
        expect(area.keywords, isNotEmpty, reason: area.id);
        for (final topic in area.topics) {
          expect(topic.id, startsWith('${area.id}.'));
          expect(topic.keywords, isNotEmpty, reason: topic.id);
          expect(topic.label.trim(), topic.label);
        }
      }
    });

    test('no single-character match terms', () {
      for (final interest in InterestCatalog.all) {
        for (final term in interest.matchTerms) {
          expect(term.runes.length, greaterThan(1), reason: interest.id);
        }
      }
    });
  });

  group('matching titles', () {
    test('a topic matches titles by its label parts and keywords', () {
      final rail = InterestCatalog.find('transport.rail')!;
      expect(mentionsAny('지하철 9호선 조기 착공', rail.matchTerms), isTrue);
      expect(mentionsAny('부산~양산~울산 광역철도 건설', rail.matchTerms), isTrue);
      expect(mentionsAny('GTX-C 노선 연장', rail.matchTerms), isTrue);
      expect(mentionsAny('공영주차장 증설', rail.matchTerms), isFalse);
    });

    test('a whole 분야 matches any of its topics', () {
      final transport = InterestCatalog.find('transport')!;
      expect(mentionsAny('공영주차장 증설', transport.matchTerms), isTrue);
      expect(mentionsAny('심야버스 노선 확대', transport.matchTerms), isTrue);
    });

    test('keepRelevant keeps the matching items first, in their order', () {
      final titles = [for (var i = 0; i < 10; i++) '기타 사업 $i']
        ..insert(8, '심야버스 노선 확대');
      final kept = keepRelevant(
        titles,
        text: (t) => t,
        terms: InterestCatalog.find('transport.bus')!.matchTerms,
        cap: 3,
      );
      expect(kept, ['기타 사업 0', '기타 사업 1', '심야버스 노선 확대']);
    });

    test('keepRelevant changes nothing when everything fits', () {
      final titles = ['a', 'b'];
      expect(
        keepRelevant(titles, text: (t) => t, terms: const ['x'], cap: 5),
        same(titles),
      );
    });
  });
}
