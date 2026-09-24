import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:democracy/src/features/history/domain/history_repository.dart';

class RemoteHistoryRepository implements HistoryRepository {
  const RemoteHistoryRepository(this.client);

  final BffClient client;

  @override
  Future<HistoryRecord> loadHistory(String districtId) async {
    final response = await client.get(
      '/districts/${Uri.encodeComponent(districtId)}/history',
      cacheable: true,
    );
    return HistoryRecord.fromJson(response.data);
  }
}
