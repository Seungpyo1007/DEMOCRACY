import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';

abstract interface class ReviewRepository {
  Future<ReviewBoard> loadBoard(String districtId);

  /// Posts a review and returns the board as it stands afterwards.
  ///
  /// Returning the board rather than void because the summary moves when a
  /// review lands -- the average and the respondent count both change -- and a
  /// caller that had to refetch could show the old numbers beside the new
  /// review.
  Future<ReviewBoard> submit(String districtId, ReviewDraft draft);
}

abstract interface class CommunityRepository {
  /// The district channel. A stream because the real one is a socket, and a
  /// screen built against a list would have to be rewritten to receive.
  Stream<List<ChatMessage>> watchChannel(String districtId);

  Future<void> send(String districtId, String body);

  Future<List<DiscussionThread>> loadThreads(String districtId);
}
