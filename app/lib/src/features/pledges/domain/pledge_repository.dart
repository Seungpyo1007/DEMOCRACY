import 'package:democracy/src/features/pledges/domain/pledge.dart';

abstract interface class PledgeRepository {
  Future<PledgeBoard> loadBoard(String districtId);
}
