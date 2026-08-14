import 'package:democracy/src/features/reviews/domain/resident_review.dart';

/// A review being written.
///
/// Separate from [ResidentReview] because a draft is allowed to be incomplete
/// and a posted review is not. Keeping them one type would mean every reader
/// of a review has to handle a half-finished one.
class ReviewDraft {
  const ReviewDraft({
    this.scores = const {},
    this.body = '',
    this.anonymous = true,
  });

  /// The four the guide names. Ratings are per axis, not one overall star, so
  /// a resident who thinks well of one thing and badly of another can say so
  /// instead of averaging it themselves.
  static const axes = <String>['소통', '공약이행', '지역발전', '도덕성'];

  static const minScore = 1;
  static const maxScore = 5;
  static const minBodyLength = 10;

  final Map<String, int> scores;
  final String body;

  /// Anonymous is the default, and the guide says it cannot be changed after
  /// posting. Defaulting to real-name would make the irreversible choice the
  /// one a resident makes by not noticing.
  final bool anonymous;

  bool get hasEveryAxis =>
      axes.every((axis) => (scores[axis] ?? 0) >= minScore);

  bool get hasBody => body.trim().length >= minBodyLength;

  bool get isComplete => hasEveryAxis && hasBody;

  /// What is still missing, for the sheet to say rather than just disabling
  /// the button and leaving the author to guess.
  String? get blockedReason {
    if (!hasEveryAxis) {
      return '네 항목 모두 별점을 매겨 주세요.';
    }
    if (!hasBody) {
      return '본문을 $minBodyLength자 이상 적어 주세요.';
    }
    return null;
  }

  double get average {
    if (scores.isEmpty) {
      return 0;
    }
    final total = scores.values.fold<int>(0, (sum, score) => sum + score);
    return total / scores.length;
  }

  ReviewDraft withScore(String axis, int score) {
    return ReviewDraft(
      scores: {...scores, axis: score.clamp(minScore, maxScore)},
      body: body,
      anonymous: anonymous,
    );
  }

  ReviewDraft withBody(String value) =>
      ReviewDraft(scores: scores, body: value, anonymous: anonymous);

  ReviewDraft withAnonymous(bool value) =>
      ReviewDraft(scores: scores, body: body, anonymous: value);
}

/// Why a piece of writing was held back before it was sent.
///
/// The guide asks for detection *before* sending rather than moderation after,
/// so this is an interception the author can act on, not a report someone else
/// files about them.
enum ContentWarning {
  hate('혐오 표현으로 감지된 문장이 있습니다.'),
  misinformation('사실과 다를 수 있는 주장이 포함돼 있습니다.');

  const ContentWarning(this.message);

  final String message;
}

/// A minimal stand-in for the server-side classifier.
///
/// Deliberately crude and deliberately client-side only for now: the real
/// check belongs on the BFF where it cannot be edited out of the app. What
/// this exists to build is the interception, not the model.
abstract final class ContentGuard {
  static const _hateTerms = ['멍청', '쓰레기 같은', '꺼져'];
  static const _claimTerms = ['확실히 조작', '무조건 거짓'];

  static ContentWarning? inspect(String text) {
    final normalised = text.replaceAll(' ', '');
    for (final term in _hateTerms) {
      if (normalised.contains(term.replaceAll(' ', ''))) {
        return ContentWarning.hate;
      }
    }
    for (final term in _claimTerms) {
      if (normalised.contains(term.replaceAll(' ', ''))) {
        return ContentWarning.misinformation;
      }
    }
    return null;
  }
}

/// One message in the district channel.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.body,
    required this.verifiedResident,
    required this.mine,
  });

  final String id;
  final String author;
  final String body;
  final bool verifiedResident;
  final bool mine;
}

/// A thread opened by a bill or a judgement.
class DiscussionThread {
  const DiscussionThread({
    required this.id,
    required this.title,
    required this.origin,
    required this.replies,
  });

  factory DiscussionThread.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A thread must be an object.');
    }

    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw const FormatException('A thread needs an id and a title.');
    }

    return DiscussionThread(
      id: id,
      title: title,
      origin: json['origin'] as String? ?? '',
      replies: json['replies'] is int ? json['replies']! as int : 0,
    );
  }

  final String id;
  final String title;

  /// What opened it -- a bill, a reversal. Threads are generated from events
  /// rather than started by whoever posts first, so no one owns the framing.
  final String origin;

  final int replies;
}
