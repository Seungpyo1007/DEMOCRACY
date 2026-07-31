import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';

class FakePledgeRepository implements PledgeRepository {
  const FakePledgeRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<PledgeBoard> loadBoard(String districtId) async {
    final payload = await loader.load('pledges_$districtId');
    return PledgeBoard.fromJson(payload);
  }
}
