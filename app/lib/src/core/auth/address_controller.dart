import 'package:democracy/src/core/auth/address_state.dart';
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

class AddressController extends Notifier<AddressState> {
  @override
  AddressState build() => const AddressState.initial();

  void continueReadOnly({DistrictRef? district}) {
    state = AddressState.readOnly(district: district);
  }

  void requestVerification({required DistrictRef district}) {
    state = AddressState.pending(district: district);
  }

  void acceptVerification({
    required DistrictRef district,
    required ResidencyVerificationProof proof,
  }) {
    state = AddressState.verified(district: district, proof: proof);
  }
}
