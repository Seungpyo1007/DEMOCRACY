import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final addressControllerProvider =
    NotifierProvider<AddressController, AddressState>(AddressController.new);

/// The district everything else is keyed to.
///
/// Every feature provider watches this rather than selecting the district out
/// of [addressControllerProvider] itself. Six copies of the same select is six
/// places to forget one when the address state grows a field -- and this is the
/// seam the spec names for refreshing every screen at once.
final districtProvider = Provider<DistrictRef?>(
  (ref) => ref.watch(addressControllerProvider.select((s) => s.district)),
);

/// Reads the stored session once, before the first route is parsed.
///
/// The router decides where a launch lands by reading the district
/// synchronously, so the restore has to finish before the router is built
/// rather than race it. `DemocracyApp` holds the frame until this resolves.
final addressRestoreProvider = FutureProvider<void>((ref) async {
  final stored = await ref.watch(addressStoreProvider).read();
  if (stored != null) {
    ref.read(addressControllerProvider.notifier).restore(stored);
  }
});

class AddressController extends Notifier<AddressState> {
  late final AddressPersistence _persistence;

  @override
  AddressState build() {
    _persistence = AddressPersistence(ref.watch(addressStoreProvider));
    return const AddressState.initial();
  }

  void continueReadOnly({DistrictRef? district}) {
    _set(AddressState.readOnly(district: district));
  }

  void requestVerification({required DistrictRef district}) {
    // Not persisted: an in-flight request cannot survive the process that
    // made it. [addressStateFromJson] drops the status on the way back in;
    // this drops it on the way out, so no launch can find one.
    state = AddressState.pending(district: district);
  }

  void acceptVerification({
    required DistrictRef district,
    required ResidencyVerificationProof proof,
  }) {
    _set(AddressState.verified(district: district, proof: proof));
  }

  /// Adopts a session read back from [AddressStore] at launch.
  ///
  /// It does not write: this state came from the store, and echoing it back
  /// would only be a chance to corrupt the record it was read from.
  void restore(AddressState stored) {
    state = stored;
  }

  void _set(AddressState next) {
    state = next;
    _persistence.save(next);
  }
}
