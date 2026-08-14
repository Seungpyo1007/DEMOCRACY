import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pledgeRepositoryProvider = Provider<PledgeRepository>(
  (ref) => const FakePledgeRepository(),
);

final pledgeBoardProvider = FutureProvider<PledgeBoard>((ref) async {
  final district = ref.watch(districtProvider);

  if (district == null) {
    throw StateError('No district has been selected yet.');
  }

  return ref.watch(pledgeRepositoryProvider).loadBoard(district.id);
});
