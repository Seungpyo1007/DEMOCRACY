import 'package:democracy/src/features/reviews/domain/resident_review.dart';

abstract interface class ReviewRepository {
  Future<ReviewBoard> loadBoard(String districtId);
}
