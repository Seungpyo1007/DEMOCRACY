import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/data/fake_direction_repository.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real client is wired.
final directionRepositoryProvider = Provider<DirectionRepository>(
  (ref) => const FakeDirectionRepository(),
);

final directionReportProvider = FutureProvider<DirectionReport>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(directionRepositoryProvider).loadReport(district.id);
});
