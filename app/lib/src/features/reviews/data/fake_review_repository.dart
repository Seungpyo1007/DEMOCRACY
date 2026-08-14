import 'dart:async';

import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';

/// The bundled review board, plus anything posted in this session.
///
/// Stateful, unlike the other fakes, because a write repository that forgets
/// is not a stand-in for one -- the screen has to be able to show a review
/// landing, and the summary moving with it.
class FakeReviewRepository implements ReviewRepository {
  FakeReviewRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  final List<ResidentReview> _posted = [];

  @override
  Future<ReviewBoard> loadBoard(String districtId) async {
    final payload = await loader.load('reviews_$districtId');
    final board = ReviewBoard.fromJson(payload);

    if (_posted.isEmpty) {
      return board;
    }
    return _withPosted(board);
  }

  @override
  Future<ReviewBoard> submit(String districtId, ReviewDraft draft) async {
    _posted.insert(
      0,
      ResidentReview(
        id: 'local-${_posted.length + 1}',
        author: draft.anonymous ? '익명 주민' : '나',
        body: draft.body.trim(),
        score: draft.average,
        verifiedResident: true,
      ),
    );
    return loadBoard(districtId);
  }

  /// New reviews go on top and move the aggregate with them.
  ///
  /// Recomputing rather than appending to a stored average: an average that
  /// drifts from the reviews under it is the kind of number this product
  /// exists to make checkable.
  ReviewBoard _withPosted(ReviewBoard board) {
    final reviews = [..._posted, ...board.reviews];
    final total = reviews.fold<double>(0, (sum, review) => sum + review.score);

    return ReviewBoard(
      summary: ReviewSummary(
        average: total / reviews.length,
        respondents: board.summary.respondents + _posted.length,
        axes: board.summary.axes,
      ),
      reviews: List.unmodifiable(reviews),
    );
  }
}

/// The district channel and its threads.
///
/// The channel is a broadcast stream fed by a seed plus whatever is sent in
/// this session, which is the shape a socket has. The threads are a plain
/// fetch because they are generated from bills rather than typed by anyone.
class FakeCommunityRepository implements CommunityRepository {
  FakeCommunityRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  final _controller = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];

  bool _seeded = false;

  @override
  Stream<List<ChatMessage>> watchChannel(String districtId) async* {
    if (!_seeded) {
      final payload = await loader.load('community_$districtId');
      final raw = payload['messages'];
      if (raw is List) {
        for (final message in raw.whereType<Map<String, Object?>>()) {
          _messages.add(
            ChatMessage(
              id: message['id'] as String? ?? '',
              author: message['author'] as String? ?? '익명 주민',
              body: message['body'] as String? ?? '',
              verifiedResident: message['verifiedResident'] as bool? ?? false,
              mine: false,
            ),
          );
        }
      }
      _seeded = true;
    }

    yield List.unmodifiable(_messages);
    yield* _controller.stream;
  }

  @override
  Future<void> send(String districtId, String body) async {
    _messages.add(
      ChatMessage(
        id: 'local-${_messages.length + 1}',
        author: '나',
        body: body.trim(),
        verifiedResident: true,
        mine: true,
      ),
    );
    _controller.add(List.unmodifiable(_messages));
  }

  @override
  Future<List<DiscussionThread>> loadThreads(String districtId) async {
    final payload = await loader.load('community_$districtId');
    final raw = payload['threads'];
    return List.unmodifiable(
      raw is List
          ? raw.map(DiscussionThread.fromJson)
          : const <DiscussionThread>[],
    );
  }
}
