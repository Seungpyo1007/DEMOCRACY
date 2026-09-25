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
    this.userId,
    DateTime? expiresAt,
  }) : opaqueToken = _validateToken(opaqueToken),
       verifiedAt = verifiedAt.toUtc(),
       expiresAt = expiresAt?.toUtc();

  /// A proof for a residency the account already holds, found on a device
  /// that never saw the grant. The server keeps only the token's hash, so
  /// there is no token to carry: the signed-in account is the credential.
  factory ResidencyVerificationProof.ofAccount({
    required String userId,
    required DateTime verifiedAt,
    required DateTime expiresAt,
  }) => ResidencyVerificationProof(
    opaqueToken: 'account:$userId',
    verifiedAt: verifiedAt,
    userId: userId,
    expiresAt: expiresAt,
  );

  final String opaqueToken;
  final DateTime verifiedAt;

  /// The account this residency belongs to. A proof bound to one person
  /// never survives another signing in on the same phone. Null only for a
  /// proof from a build without accounts.
  final String? userId;

  /// When the residency has to be checked again.
  final DateTime? expiresAt;

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
