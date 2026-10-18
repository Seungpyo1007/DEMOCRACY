import 'package:democracy/src/features/interests/domain/hangul.dart';
import 'package:democracy/src/features/interests/domain/interest_taxonomy.dart';

/// One thing a reader can pick: a 세부 주제, or a whole 분야.
///
/// A whole 분야 is offered as well as its topics because some readers care
/// about 교육 rather than any one part of it, and because the old flat list
/// had exactly those broad entries (복지, 교육, 청년) to carry across.
class Interest {
  const Interest._({required this.area, this.topic});

  final InterestArea area;

  /// Null for the whole 분야.
  final InterestTopic? topic;

  String get id => topic?.id ?? area.id;
  String get label => topic?.label ?? area.label;
  bool get isWholeArea => topic == null;

  /// The words to search and match by beyond the label itself.
  List<String> get keywords => topic?.keywords ?? area.keywords;

  /// Every word that marks a pledge or bill title as about this interest:
  /// the label's own parts (`지하철·광역철도` → 지하철, 광역철도) and the
  /// keywords. A whole 분야 takes in all of its topics' words too.
  ///
  /// Single-character words are left out: `집` or `군` would mark half of
  /// all titles (군청, 집중) as relevant.
  List<String> get matchTerms {
    final words = <String>{
      ..._labelParts(label),
      ...keywords,
      if (isWholeArea)
        for (final topic in area.topics) ...[
          ..._labelParts(topic.label),
          ...topic.keywords,
        ],
    };
    return [
      for (final word in words)
        if (word.trim().runes.length >= 2) word.trim(),
    ];
  }

  /// A short list for the model to read beside the label: what else the
  /// reader means by it. A whole 분야 lists its topics by name.
  List<String> get promptTerms {
    final terms = isWholeArea
        ? [for (final topic in area.topics) topic.label]
        : [
            for (final word in keywords)
              if (!_labelParts(label).contains(word)) word,
          ];
    return terms.take(maxPromptTerms).toList(growable: false);
  }

  /// Enough to steer the model without crowding out the pledges in a small
  /// context window.
  static const maxPromptTerms = 6;

  @override
  String toString() => 'Interest($id)';
}

List<String> _labelParts(String label) => [
  for (final part in label.split('·'))
    if (part.trim().isNotEmpty) part.trim(),
];

/// The taxonomy flattened into what a reader picks from, in display order:
/// each 분야, then its topics.
abstract final class InterestCatalog {
  static final List<Interest> all = List.unmodifiable([
    for (final area in interestAreas) ...[
      Interest._(area: area),
      for (final topic in area.topics) Interest._(area: area, topic: topic),
    ],
  ]);

  static final Map<String, Interest> _byId = {
    for (final interest in all) interest.id: interest,
  };

  static final Map<String, int> _order = {
    for (final (i, interest) in all.indexed) interest.id: i,
  };

  static Interest? find(String id) => _byId[id];

  /// The interest for [area] as a whole.
  static Interest wholeArea(InterestArea area) => _byId[area.id]!;

  /// The topics of [area], without the whole-분야 entry.
  static List<Interest> topicsOf(InterestArea area) => [
    for (final topic in area.topics) _byId[topic.id]!,
  ];

  /// [ids] cleaned up for storage and for the match: unknown ids dropped,
  /// repeats dropped, in catalog order.
  ///
  /// Catalog order rather than the order they were tapped, so the same
  /// choice always makes the same match input -- and hits the same cached
  /// answer -- however it was arrived at.
  static List<String> normalise(Iterable<String> ids) {
    final known = {
      for (final id in ids)
        if (_byId.containsKey(id)) id,
    }.toList()..sort((a, b) => _order[a]! - _order[b]!);
    return List.unmodifiable(known);
  }
}

/// The interests matching [query], best first.
///
/// Matches the label, the keywords and the 분야 name, each by
/// [hangulIndexOf] -- so 초성 (`ㄱㅌ`), a half-typed syllable and a synonym
/// (`GTX`, `전세 사기`) all find something. A label hit outranks a keyword
/// hit, and a hit at the start of the label outranks one inside it; ties keep
/// catalog order, so 교통 comes before its own topics.
List<Interest> searchInterests(String query) {
  if (normaliseForSearch(query).isEmpty) {
    return const [];
  }
  final scored = <(Interest, int)>[];
  for (final interest in InterestCatalog.all) {
    final score = _score(interest, query);
    if (score > 0) {
      scored.add((interest, score));
    }
  }
  // List.sort is not stable; the index keeps catalog order on ties.
  final indexed = scored.indexed.toList()
    ..sort((a, b) {
      final byScore = b.$2.$2 - a.$2.$2;
      return byScore != 0 ? byScore : a.$1 - b.$1;
    });
  return [for (final (_, (interest, _)) in indexed) interest];
}

int _score(Interest interest, String query) {
  final label = hangulIndexOf(interest.label, query);
  if (label == 0) {
    return normaliseForSearch(interest.label) == normaliseForSearch(query)
        ? 100
        : 80;
  }
  if (label > 0) {
    return 60;
  }
  if (interest.keywords.any((word) => hangulContains(word, query))) {
    return 40;
  }
  if (!interest.isWholeArea && hangulContains(interest.area.label, query)) {
    return 20;
  }
  return 0;
}

/// What the flat list before the 분야 > 세부 주제 taxonomy held, and where
/// each of its policy chips lands now. One to one, so a reader who had all
/// five keeps five and stays inside the limit.
///
/// 부동산 and 세금 were narrow enough to be topics; 복지, 교육 and 청년 were
/// whole fields and stay whole fields.
const legacyInterestIds = {
  '부동산': 'housing.market',
  '세금': 'economy.tax',
  '복지': 'welfare',
  '교육': 'education',
  '청년': 'youth',
};

/// Reads ids that may come from an older build: a current id is kept, an
/// old chip label is mapped through [legacyInterestIds], anything else is
/// dropped. Returned through [InterestCatalog.normalise].
List<String> migrateInterestIds(Iterable<String> stored) =>
    InterestCatalog.normalise([
      for (final entry in stored) legacyInterestIds[entry] ?? entry,
    ]);

/// Whether [text] -- a pledge or bill title -- mentions any of [terms].
///
/// Plain substring, case-insensitive for the Latin ones (GTX, RE100). No
/// 초성 or half-typed matching here: titles are complete words.
bool mentionsAny(String text, Iterable<String> terms) {
  final haystack = text.toLowerCase();
  return terms.any((term) => haystack.contains(term.toLowerCase()));
}

/// Up to [cap] of [items], the ones mentioning [terms] first, returned in
/// their original order.
///
/// A district can have more pledges and bills than an on-device run has
/// room for. Cutting by position alone dropped whatever came last; this
/// keeps every item that names the reader's interests, then fills the rest
/// by position, so the model is not asked about 교통 with the 교통 pledges
/// cut off.
List<T> keepRelevant<T>(
  List<T> items, {
  required String Function(T) text,
  required Iterable<String> terms,
  required int cap,
}) {
  if (items.length <= cap) {
    return items;
  }
  final termList = terms.toList(growable: false);
  final chosen = <int>{};
  for (final (i, item) in items.indexed) {
    if (chosen.length == cap) {
      break;
    }
    if (mentionsAny(text(item), termList)) {
      chosen.add(i);
    }
  }
  for (var i = 0; i < items.length && chosen.length < cap; i++) {
    chosen.add(i);
  }
  return [
    for (final (i, item) in items.indexed)
      if (chosen.contains(i)) item,
  ];
}
