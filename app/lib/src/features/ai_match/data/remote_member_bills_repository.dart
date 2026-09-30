import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';

/// The sitting member's recent bills from the BFF (`/districts/{id}/bills`).
///
/// Public record, so the last answer is kept for offline reading like the
/// profile's. A district with no sitting member answers `not_found`, which
/// the client raises as NotAvailableException.
class RemoteMemberBillsRepository implements MemberBillsRepository {
  const RemoteMemberBillsRepository(this.client);

  final BffClient client;

  @override
  Future<MemberBills> loadRecent(String districtId, {int months = 6}) async {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/bills',
      query: {'months': '$months'},
      cacheable: true,
    );
    return MemberBills.fromJson(response.data);
  }
}
