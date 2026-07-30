enum AddressStatus { unverified, pending, verified }

class DistrictRef {
  const DistrictRef({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class ResidencyVerificationProof {
  ResidencyVerificationProof({
    required String opaqueToken,
    required DateTime verifiedAt,
  }) : opaqueToken = _validateToken(opaqueToken),
       verifiedAt = verifiedAt.toUtc();

  final String opaqueToken;
  final DateTime verifiedAt;

  static String _validateToken(String opaqueToken) {
    if (opaqueToken.trim().isEmpty) {
      throw ArgumentError.value(
        opaqueToken,
        'opaqueToken',
        'A non-empty server-issued verification token is required.',
      );
    }
    return opaqueToken;
  }
}

class AddressState {
  const AddressState.initial()
    : status = AddressStatus.unverified,
      district = null,
      verification = null;

  const AddressState.readOnly({this.district})
    : status = AddressStatus.unverified,
      verification = null;

  const AddressState.pending({required DistrictRef this.district})
    : status = AddressStatus.pending,
      verification = null;

  const AddressState.verified({
    required DistrictRef this.district,
    required ResidencyVerificationProof proof,
  }) : status = AddressStatus.verified,
       verification = proof;

  final AddressStatus status;
  final DistrictRef? district;
  final ResidencyVerificationProof? verification;

  bool get isVerified =>
      status == AddressStatus.verified && verification != null;
}
