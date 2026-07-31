import 'package:democracy/src/core/provenance/source_metadata.dart';

/// One resident's rating on a single axis.
class ReviewAxis {
  const ReviewAxis({required this.label, required this.score});

  factory ReviewAxis.fromJson(Map<String, Object?> json) {
    final label = json['label'];
    final score = json['score'];
    if (label is! String || score is! num) {
      throw const MissingSourceException(
        field: 'reviewAxis',
        reason: 'label and score are required.',
      );
    }
    return ReviewAxis(label: label, score: score.toDouble());
  }

  final String label;
  final double score;

  /// Rendered out of five, descriptive only.
  String get display => score.toStringAsFixed(1);
}

/// Aggregate resident sentiment.
///
/// This is community-generated rather than an external figure, so it carries
/// no SourceMetadata. The distinction matters: attaching a fake official
/// source to opinion data would be worse than attaching none.
class ReviewSummary {
  const ReviewSummary({
    required this.average,
    required this.respondents,
    required this.axes,
  });

  factory ReviewSummary.fromJson(Map<String, Object?> json) {
    final average = json['average'];
    final respondents = json['respondents'];
    if (average is! num || respondents is! int) {
      throw const MissingSourceException(
        field: 'reviewSummary',
        reason: 'average and respondents are required.',
      );
    }

    final rawAxes = json['axes'];
    return ReviewSummary(
      average: average.toDouble(),
      respondents: respondents,
      axes: List.unmodifiable(<ReviewAxis>[
        if (rawAxes is List)
          for (final axis in rawAxes)
            ReviewAxis.fromJson(axis as Map<String, Object?>),
      ]),
    );
  }

  final double average;
  final int respondents;
  final List<ReviewAxis> axes;

  String get averageDisplay => average.toStringAsFixed(1);

  String get respondentsDisplay => '주민 $respondents명 평가';
}

class ResidentReview {
  const ResidentReview({
    required this.id,
    required this.author,
    required this.body,
    required this.score,
    required this.verifiedResident,
  });

  factory ResidentReview.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final body = json['body'];
    final score = json['score'];
    if (id is! String || body is! String || score is! num) {
      throw const MissingSourceException(
        field: 'residentReview',
        reason: 'id, body and score are required.',
      );
    }

    return ResidentReview(
      id: id,
      author: json['author'] as String? ?? '익명 주민',
      body: body,
      score: score.toDouble(),
      verifiedResident: json['verifiedResident'] as bool? ?? false,
    );
  }

  final String id;
  final String author;
  final String body;
  final double score;
  final bool verifiedResident;
}

class ReviewBoard {
  const ReviewBoard({required this.summary, required this.reviews});

  factory ReviewBoard.fromJson(Map<String, Object?> json) {
    final rawReviews = json['reviews'];
    return ReviewBoard(
      summary: ReviewSummary.fromJson(
        json['summary'] as Map<String, Object?>? ?? const {},
      ),
      reviews: List.unmodifiable(<ResidentReview>[
        if (rawReviews is List)
          for (final review in rawReviews)
            ResidentReview.fromJson(review as Map<String, Object?>),
      ]),
    );
  }

  final ReviewSummary summary;
  final List<ResidentReview> reviews;
}
