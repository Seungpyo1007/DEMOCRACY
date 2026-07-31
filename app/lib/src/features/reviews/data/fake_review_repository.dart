import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';

class FakeReviewRepository implements ReviewRepository {
  const FakeReviewRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<ReviewBoard> loadBoard(String districtId) async {
    final payload = await loader.load('reviews_$districtId');
    return ReviewBoard.fromJson(payload);
  }
}
