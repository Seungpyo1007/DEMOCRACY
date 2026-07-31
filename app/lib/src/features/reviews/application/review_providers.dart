import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => const FakeReviewRepository(),
);

final reviewBoardProvider = FutureProvider<ReviewBoard>((ref) async {
  final district = ref.watch(
    addressControllerProvider.select((state) => state.district),
  );

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(reviewRepositoryProvider).loadBoard(district.id);
});
