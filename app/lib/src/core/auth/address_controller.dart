import 'package:democracy/src/core/auth/address_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final addressControllerProvider =
    NotifierProvider<AddressController, AddressState>(AddressController.new);

final districtProvider = Provider<DistrictRef?>(
  (ref) => ref.watch(addressControllerProvider).district,
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
    state = AddressState.verified(
      district: district,
      proof: proof,
    );
  }
}
