import 'package:democracy/src/core/auth/address_state.dart';

/// One result from an address lookup.
///
/// [district] is what the app actually keeps. [address] is the string the user
/// recognises and is shown only to let them confirm the match -- the guide is
/// explicit that a raw address is not retained, so nothing downstream takes
/// this type.
class AddressSuggestion {
  const AddressSuggestion({required this.address, required this.district});

  factory AddressSuggestion.fromJson(Map<String, Object?> json) {
    final address = json['address'];
    final district = json['district'];

    if (address is! String || address.trim().isEmpty) {
      throw const FormatException('An address suggestion needs an address.');
    }
    if (district is! Map) {
      throw const FormatException('An address suggestion needs a district.');
    }

    final id = district['id'];
    final displayName = district['displayName'];
    if (id is! String || id.isEmpty || displayName is! String) {
      throw const FormatException('A district needs an id and a name.');
    }

    return AddressSuggestion(
      address: address,
      district: DistrictRef(id: id, displayName: displayName),
    );
  }

  final String address;
  final DistrictRef district;
}

abstract interface class AddressSearchRepository {
  /// Results for [query], or empty when nothing matches.
  Future<List<AddressSuggestion>> search(String query);
}

/// Why a location lookup did not produce a district.
///
/// Modelled as an outcome rather than an exception because every one of these
/// has a different thing to say to the user, and the guide requires a manual
/// fallback rather than an error.
enum LocationFailure {
  permissionDenied('위치 권한이 없어 자동 설정을 할 수 없습니다.'),
  permissionDeniedForever('설정에서 위치 권한을 허용하면 자동 설정을 쓸 수 있습니다.'),
  serviceDisabled('기기의 위치 서비스가 꺼져 있습니다.'),
  noMatch('현재 위치에서 지역구를 찾지 못했습니다.'),
  failed('현재 위치를 확인하지 못했습니다.');

  const LocationFailure(this.message);

  /// Shown next to the manual search field, which stays available throughout.
  final String message;
}

/// The result of asking the device where it is.
sealed class LocationResult {
  const LocationResult();
}

class LocationResolved extends LocationResult {
  const LocationResolved(this.district);

  final DistrictRef district;
}

class LocationRejected extends LocationResult {
  const LocationRejected(this.failure);

  final LocationFailure failure;
}

abstract interface class LocationRepository {
  /// Asks for permission if needed, reads a position, and reverse-geocodes it
  /// to a district.
  ///
  /// Never throws for a denial: a user who refuses location is expected, not
  /// exceptional, and the screen has a manual path for them.
  Future<LocationResult> detectDistrict();
}
