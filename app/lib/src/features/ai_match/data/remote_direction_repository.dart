import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';

/// The direction view from the BFF.
///
/// Today the server fills in the incumbent's bill field trend only -- a
/// count over committee referrals, no model involved -- and sends the two
/// model-derived blocks as null, which the screen shows as 준비 중. A
/// district with no incumbent on record answers `not_found`, which the
/// client raises as NotAvailableException.
class RemoteDirectionRepository implements DirectionRepository {
  const RemoteDirectionRepository(this.client);

  final BffClient client;

  @override
  Future<DirectionReport> loadReport(String districtId) async {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/direction',
      cacheable: true,
    );
    return DirectionReport.fromJson(response.data);
  }
}
