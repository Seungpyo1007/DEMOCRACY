import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => FakeReviewRepository(),
);

final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => FakeCommunityRepository(),
);

final reviewBoardProvider = FutureProvider<ReviewBoard>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(reviewRepositoryProvider).loadBoard(district.id);
});

/// Posts a review, then refreshes the board so the summary moves with it.
final reviewSubmissionProvider =
    NotifierProvider<ReviewSubmissionController, AsyncValue<void>>(
      ReviewSubmissionController.new,
    );

class ReviewSubmissionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<bool> submit(ReviewDraft draft) async {
    final district = ref.read(addressControllerProvider).district;
    if (district == null || !draft.isComplete) {
      return false;
    }

    state = const AsyncValue.loading();
    try {
      await ref.read(reviewRepositoryProvider).submit(district.id, draft);
      ref.invalidate(reviewBoardProvider);
      state = const AsyncValue.data(null);
      return true;
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
      return false;
    }
  }
}

final channelProvider = StreamProvider<List<ChatMessage>>((ref) {
  final district = ref.watch(districtProvider);

  if (district == null) {
    return const Stream.empty();
  }

  return ref.watch(communityRepositoryProvider).watchChannel(district.id);
});

final discussionThreadsProvider = FutureProvider<List<DiscussionThread>>((
  ref,
) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    return const [];
  }

  return ref.watch(communityRepositoryProvider).loadThreads(district.id);
});
