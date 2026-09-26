import 'package:democracy/src/features/history/domain/history_record.dart';

/// What the history screen is allowed to depend on.
///
/// Screens talk to this and never to a transport, so swapping the fake for a
/// REST implementation later is a wiring change rather than a screen change.
abstract interface class HistoryRepository {
  Future<HistoryRecord> loadHistory(String districtId);
}
