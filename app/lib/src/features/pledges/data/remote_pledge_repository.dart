import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';

/// Curated pledges, where a district has them.
///
/// Assembly pledges have no public API -- they exist as election-bulletin
/// PDFs -- so they are entered by hand, district by district. A district not
/// done yet answers `not_curated`, which the client raises as
/// NotAvailableException and the screen shows as 준비 중.
class RemotePledgeRepository implements PledgeRepository {
  const RemotePledgeRepository(this.client);

  final BffClient client;

  @override
  Future<PledgeBoard> loadBoard(String districtId) async {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/pledges',
      cacheable: true,
    );
    return PledgeBoard.fromJson(response.data);
  }
}
