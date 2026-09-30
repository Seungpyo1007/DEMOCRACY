import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';

/// Whether an input line is a pledge, a bill or a discussion thread.
enum CitedKind { pledge, bill, thread }

/// One line of public text the model is shown, under a short key.
///
/// The model sees `P3 환승 개선 사업`, never the real id: a two-character key
/// is cheap in a small context window and hard to misspell, and anything it
/// cites is looked up here. A key that is not in the table is a citation of
/// something the reader was never shown, and is dropped.
class CitedItem {
  const CitedItem({
    required this.key,
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    this.category,
    this.month,
  });

  /// `P1`, `B1`, `I1`.
  final String key;

  /// The real id: the pledge's, the bill's or the thread's.
  final String id;
  final String title;
  final CitedKind kind;
  final SourceMetadata source;

  /// The pledge's own category (교통, 복지), shown to the model as context.
  final String? category;

  /// `YYYY-MM` (KST), for text counted by month.
  final String? month;

  /// The line the model reads.
  String get line => category == null || category!.isEmpty
      ? '$key $title'
      : '$key [$category] $title';

  /// What the cache key hashes: everything that could change the answer.
  Map<String, Object?> toFingerprint() => {
    'k': key,
    'id': id,
    't': title,
    if (category != null) 'c': category,
    if (month != null) 'm': month,
  };
}

/// Keys pledges `P1…` in the board's order.
List<CitedItem> pledgeItems(Iterable<Pledge> pledges) => [
  for (final (i, pledge) in pledges.indexed)
    CitedItem(
      key: 'P${i + 1}',
      id: pledge.id,
      title: pledge.title,
      category: pledge.category,
      kind: CitedKind.pledge,
      source: pledge.source,
    ),
];

/// Keys bills `B1…`, newest first as served.
List<CitedItem> billItems(Iterable<BillDigest> bills) => [
  for (final (i, bill) in bills.indexed)
    CitedItem(
      key: 'B${i + 1}',
      id: bill.id,
      title: bill.title,
      kind: CitedKind.bill,
      source: bill.source,
      month: bill.month,
    ),
];

/// A lookup from key to item.
Map<String, CitedItem> byKey(Iterable<CitedItem> items) => {
  for (final item in items) item.key: item,
};

/// The key the model wrote, normalised: `p3`, ` P3 `, `[P3]` → `P3`.
String? normaliseKey(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final match = RegExp(r'([PBI])\s*(\d{1,3})').firstMatch(raw.toUpperCase());
  return match == null ? null : '${match[1]}${int.parse(match[2]!)}';
}
