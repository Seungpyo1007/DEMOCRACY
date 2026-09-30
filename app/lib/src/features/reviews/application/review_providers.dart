import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/community_write_failure.dart';
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
///
/// Scoped to the compose page, so a refusal shown there is not still showing
/// the next time the page opens.
final reviewSubmissionProvider =
    NotifierProvider.autoDispose<ReviewSubmissionController, AsyncValue<void>>(
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
      await settleWriteFailure(
        error,
        onSessionExpired: () =>
            ref.read(authControllerProvider.notifier).sessionExpired(),
        onResidencyLost: () =>
            ref.read(addressControllerProvider.notifier).dropResidency(),
      );
      state = AsyncValue.error(error, stack);
      return false;
    }
  }
}

/// Lets the rest of the app know what a refused write means.
///
/// A refused session signs out (the app then offers to sign in again); a
/// residency the server no longer holds stops being shown, so the next tap
/// opens the gate instead of a page whose post would be refused again.
Future<void> settleWriteFailure(
  Object error, {
  required Future<void> Function() onSessionExpired,
  required void Function() onResidencyLost,
}) async {
  if (error is SessionExpiredException) {
    await onSessionExpired();
  } else if (error is CommunityWriteException && error.residencyLost) {
    onResidencyLost();
  }
}

/// What the author reads when a review or a message did not post.
String writeFailureMessage(Object error) => switch (error) {
  SessionExpiredException() => '로그인이 만료됐습니다. 다시 로그인한 뒤 올려 주세요.',
  CommunityWriteException(:final message) => message,
  _ => CommunityWriteException.generic.message,
};

/// The open district channel, kept current while anything watches it.
///
/// Disposed when the channel tab stops being shown, which cancels the stream
/// and so closes its socket; opening the tab again reads the channel afresh.
final channelProvider = StreamProvider.autoDispose<List<ChatMessage>>((ref) {
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
