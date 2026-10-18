import 'package:democracy/src/features/district/domain/legislator_record.dart';

/// A bill whose title shares words with a pledge's title.
///
/// This is a string match and nothing more. A shared word says the two
/// titles name the same subject; it does not say the bill carries out the
/// pledge, and nothing built on this may present it as if it did.
class BillOverlap {
  const BillOverlap({required this.bill, required this.keywords});

  final BillEntry bill;

  /// The pledge's own words that appear in the bill's title, in the order
  /// the pledge uses them.
  final List<String> keywords;
}

/// Words too common in pledge and bill titles to say anything about the
/// subject: what is done (지원, 확대) and the bill's own boilerplate (일부개정
/// 법률안). Matching on them would pair every 지원 pledge with every 지원 bill.
const _generic = {
  '지원', '확대', '개선', '설치', '조성', '추진', '강화', '사업', '확충', '증설', //
  '운영', '연장', '정비', '지정', '연결', '대책', '도입', '마련', '건립', '구축', //
  '신설', '확장', '활성화', '유치', '착공', '조기', '완공', '개발', '건설', '확보', //
  '예방', '관한', '위한', '대한', '등의', '법률', '법률안', '법안', '개정', '개정안', //
  '일부개정', '일부개정안', '일부개정법률안', '전부개정법률안', '특별법', '특별법안', //
  '제정', '제정안', '지역', '우리', '주민',
};

/// The words in a pledge title worth matching on: two characters or more,
/// and not in [_generic].
List<String> pledgeKeywords(String title) {
  final seen = <String>{};
  return [
    for (final word in title.split(RegExp(r'[^0-9A-Za-z가-힣]+')))
      if (word.length >= 2 &&
          !_generic.contains(word) &&
          seen.add(word.toLowerCase()))
        word,
  ];
}

/// The [bills] whose titles contain at least one of the pledge's keywords,
/// most shared words first and otherwise in the order given.
///
/// Containment rather than whole-word equality, since Korean titles run
/// words together: 「청년」 in a pledge is the same subject as 「청년주택」 in
/// a bill.
List<BillOverlap> billsSharingKeywords(
  String pledgeTitle,
  Iterable<BillEntry> bills, {
  int limit = 5,
}) {
  final keywords = pledgeKeywords(pledgeTitle);
  if (keywords.isEmpty) {
    return const [];
  }

  final matches = <BillOverlap>[];
  for (final bill in bills) {
    final title = bill.title.toLowerCase();
    final shared = [
      for (final keyword in keywords)
        if (title.contains(keyword.toLowerCase())) keyword,
    ];
    if (shared.isNotEmpty) {
      matches.add(BillOverlap(bill: bill, keywords: shared));
    }
  }

  // List.sort is not stable, so the original position breaks ties.
  final order = {for (var i = 0; i < matches.length; i++) matches[i]: i};
  matches.sort((a, b) {
    final byCount = b.keywords.length.compareTo(a.keywords.length);
    return byCount != 0 ? byCount : order[a]!.compareTo(order[b]!);
  });

  return List.unmodifiable(matches.take(limit));
}
