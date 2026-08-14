import 'package:democracy/src/core/provenance/source_metadata.dart';

/// One bill, at whatever stage it has reached.
///
/// [stage] is the parliament's own wording, not a judgement of it. Nothing
/// here says whether a bill is good or its progress adequate -- the resident
/// is given the stage and the date and draws their own conclusion.
class BillEntry {
  const BillEntry({
    required this.id,
    required this.title,
    required this.stage,
    required this.stamp,
  });

  factory BillEntry.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'bill',
        reason: 'A bill must be an object.',
      );
    }

    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw const MissingSourceException(
        field: 'bill',
        reason: 'A bill needs an id and a title.',
      );
    }

    return BillEntry(
      id: id,
      title: title,
      stage: json['stage'] is String ? json['stage']! as String : '',
      stamp: json['stamp'] is String ? json['stamp']! as String : '',
    );
  }

  final String id;
  final String title;
  final String stage;
  final String stamp;
}

class BillRecord {
  const BillRecord({required this.items, required this.source});

  factory BillRecord.fromJson(Object? json, {required String field}) {
    if (json is! Map) {
      throw MissingSourceException(
        field: field,
        reason: 'A bill record must be an object.',
      );
    }

    final raw = json['items'];
    return BillRecord(
      items: List.unmodifiable(
        raw is List ? raw.map(BillEntry.fromJson) : const <BillEntry>[],
      ),
      source: SourceMetadata.fromJson(json['source'], field: field),
    );
  }

  final List<BillEntry> items;
  final SourceMetadata source;

  int get total => items.length;
}

/// One reading in a series, e.g. attendance in a given month.
class ActivityPoint {
  const ActivityPoint({required this.label, required this.value});

  factory ActivityPoint.fromJson(Object? json) {
    if (json is! Map) {
      throw const MissingSourceException(
        field: 'activityPoint',
        reason: 'A point must be an object.',
      );
    }

    final label = json['label'];
    final value = json['value'];
    if (label is! String || label.isEmpty || value is! num) {
      throw const MissingSourceException(
        field: 'activityPoint',
        reason: 'A point needs a label and a numeric value.',
      );
    }

    return ActivityPoint(label: label, value: value.toDouble());
  }

  final String label;
  final double value;
}

/// A figure over time, drawn as a sparkline.
///
/// The source sits on the series rather than on each reading. A per-point
/// attribution would be noise -- the whole line comes from one query -- but
/// the series still cannot exist without one, which is the rule that matters.
class ActivitySeries {
  const ActivitySeries({
    required this.points,
    required this.unit,
    required this.source,
  });

  factory ActivitySeries.fromJson(Object? json, {required String field}) {
    if (json is! Map) {
      throw MissingSourceException(
        field: field,
        reason: 'A series must be an object.',
      );
    }

    final raw = json['points'];
    final points = List<ActivityPoint>.unmodifiable(
      raw is List ? raw.map(ActivityPoint.fromJson) : const <ActivityPoint>[],
    );

    if (points.isEmpty) {
      throw MissingSourceException(
        field: field,
        reason: 'A series needs at least one point.',
      );
    }

    return ActivitySeries(
      points: points,
      unit: json['unit'] is String ? json['unit']! as String : '',
      source: SourceMetadata.fromJson(json['source'], field: field),
    );
  }

  final List<ActivityPoint> points;
  final String unit;
  final SourceMetadata source;

  double get latest => points.last.value;

  String get latestDisplay => '${_trim(latest)}$unit';

  double get minimum =>
      points.map((point) => point.value).reduce((a, b) => a < b ? a : b);

  double get maximum =>
      points.map((point) => point.value).reduce((a, b) => a > b ? a : b);

  /// The span the chart is drawn against, padded so a flat line is not drawn
  /// on the floor and a peak is not clipped by the ceiling.
  (double, double) get bounds {
    final low = minimum;
    final high = maximum;
    if (low == high) {
      return (low - 1, high + 1);
    }
    final pad = (high - low) * 0.15;
    return (low - pad, high + pad);
  }

  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}

/// What an incumbent has actually done, behind the dashboard's inner tabs.
///
/// Optional as a whole: a candidate has no record, and an incumbent whose
/// feed has not been wired yet should degrade to the pledge tab rather than
/// fail to parse.
class LegislatorRecord {
  const LegislatorRecord({
    required this.bills,
    required this.attendance,
    required this.votes,
  });

  static LegislatorRecord? fromJson(Object? json, {required String field}) {
    if (json is! Map) {
      return null;
    }

    return LegislatorRecord(
      bills: BillRecord.fromJson(json['bills'], field: '$field.bills'),
      attendance: ActivitySeries.fromJson(
        json['attendance'],
        field: '$field.attendance',
      ),
      votes: ActivitySeries.fromJson(json['votes'], field: '$field.votes'),
    );
  }

  final BillRecord bills;
  final ActivitySeries attendance;
  final ActivitySeries votes;
}
