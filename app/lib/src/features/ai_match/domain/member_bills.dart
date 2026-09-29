import 'package:democracy/src/core/provenance/source_metadata.dart';

/// One bill the sitting member led, with its own page.
///
/// The on-device model reads [title]; when it cites the bill, the reader is
/// sent to [source] -- the bill's likms page, not the dataset it came in.
class BillDigest {
  const BillDigest({
    required this.id,
    required this.title,
    required this.proposedOn,
    required this.source,
    this.committee,
  });

  factory BillDigest.fromJson(Object? json, {required DateTime fetchedAt}) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'memberBills.bill',
        reason: 'A bill must be an object.',
      );
    }
    final id = json['id'];
    final title = json['title'];
    final proposedOn = json['proposedOn'];
    final url = json['sourceUrl'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        proposedOn is! String ||
        !_isoDate.hasMatch(proposedOn) ||
        url is! String) {
      throw const MissingSourceException(
        field: 'memberBills.bill',
        reason: 'A bill needs an id, a title, a date and its page.',
      );
    }
    // Parsed like any other provenance, so a relative or keyed link fails
    // here exactly as it would on a figure.
    final source = SourceMetadata.fromJson({
      'sourceUrl': url,
      'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    }, field: 'memberBills.bill.$id');
    return BillDigest(
      id: id,
      title: title.trim(),
      proposedOn: proposedOn,
      committee: json['committee'] is String
          ? json['committee']! as String
          : null,
      source: source,
    );
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  final String id;
  final String title;

  /// `YYYY-MM-DD`, a KST calendar date.
  final String proposedOn;

  final String? committee;
  final SourceMetadata source;

  /// `YYYY-MM`, the KST month it was proposed in.
  String get month => proposedOn.substring(0, 7);
}

/// The sitting member's bills over the last few months.
class MemberBills {
  const MemberBills({
    required this.legislatorId,
    required this.legislatorName,
    required this.since,
    required this.months,
    required this.bills,
    required this.source,
  });

  factory MemberBills.fromJson(Map<String, Object?> json) {
    final legislator = json['legislator'];
    final since = json['since'];
    if (legislator is! Map ||
        legislator['id'] is! String ||
        legislator['name'] is! String ||
        since is! String) {
      throw const MissingSourceException(
        field: 'memberBills',
        reason: 'The bills need their member and window.',
      );
    }
    final source = SourceMetadata.fromJson(
      json['source'],
      field: 'memberBills',
    );
    final raw = json['bills'];
    return MemberBills(
      legislatorId: legislator['id']! as String,
      legislatorName: legislator['name']! as String,
      since: since,
      months: json['months'] is int ? json['months']! as int : 6,
      bills: List.unmodifiable([
        if (raw is List)
          for (final bill in raw)
            BillDigest.fromJson(bill, fetchedAt: source.fetchedAt),
      ]),
      source: source,
    );
  }

  final String legislatorId;
  final String legislatorName;

  /// The first day of the window, `YYYY-MM-DD`.
  final String since;
  final int months;

  /// Newest first.
  final List<BillDigest> bills;
  final SourceMetadata source;
}

abstract interface class MemberBillsRepository {
  Future<MemberBills> loadRecent(String districtId, {int months = 6});
}
