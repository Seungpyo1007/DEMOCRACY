import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
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

/// Where the two model-made blocks come from. Null in a fixture build, whose
/// report already carries its sample blocks; the on-device model in a live
/// build.
final directionAiSourceProvider = Provider<DirectionAiSource?>((ref) => null);

/// Blocks 01 and 03 from this device's model, loaded apart from the report so
/// the server's bill trend draws at once while the model is still reading.
/// Null when there is no source.
final directionAiProvider = FutureProvider<DirectionAiBlocks?>((ref) async {
  final source = ref.watch(directionAiSourceProvider);
  final district = ref.watch(districtProvider);
  if (source == null || district == null) {
    return null;
  }
  return source.load(district.id);
}, retry: noRetry);
