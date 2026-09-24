import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:geolocator/geolocator.dart';

/// Road-name search through the BFF, which holds the juso key and maps each
/// hit to its 선거구.
///
/// Never cached: the guide says a raw address is not retained, and a cache
/// keyed by the query would retain it.
class RemoteAddressSearchRepository implements AddressSearchRepository {
  const RemoteAddressSearchRepository(this.client);

  final BffClient client;

  @override
  Future<List<AddressSuggestion>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final response = await client.get('/address/search', query: {'q': trimmed});
    final raw = response.data['suggestions'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map<String, Object?>>()
        .map(AddressSuggestion.fromJson)
        .toList(growable: false);
  }
}

/// Where the device is, as a position. A seam so the permission paths can be
/// tested without a platform channel.
abstract interface class PositionSource {
  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<bool> isServiceEnabled();

  Future<({double latitude, double longitude})> current();
}

class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<({double latitude, double longitude})> current() async {
    // A district is kilometres wide; low accuracy answers faster and asks
    // for less.
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: position.latitude, longitude: position.longitude);
  }
}

/// A position, resolved to a district by the BFF.
///
/// The position goes to the server once and is not stored on either side;
/// only the district comes back.
class RemoteLocationRepository implements LocationRepository {
  const RemoteLocationRepository(
    this.client, {
    this.positions = const GeolocatorPositionSource(),
  });

  final BffClient client;
  final PositionSource positions;

  @override
  Future<LocationResult> detectDistrict() async {
    try {
      if (!await positions.isServiceEnabled()) {
        return const LocationRejected(LocationFailure.serviceDisabled);
      }

      var permission = await positions.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await positions.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationRejected(LocationFailure.permissionDenied);
        case LocationPermission.deniedForever:
          return const LocationRejected(
            LocationFailure.permissionDeniedForever,
          );
        case LocationPermission.whileInUse:
        case LocationPermission.always:
        case LocationPermission.unableToDetermine:
          break;
      }

      final at = await positions.current();
      final response = await client.get(
        '/location/district',
        query: {
          'lat': at.latitude.toStringAsFixed(5),
          'lng': at.longitude.toStringAsFixed(5),
        },
      );
      final district = response.data['district'];
      if (district is! Map ||
          district['id'] is! String ||
          district['displayName'] is! String) {
        return const LocationRejected(LocationFailure.noMatch);
      }
      return LocationResolved(
        DistrictRef(
          id: district['id'] as String,
          displayName: district['displayName'] as String,
        ),
      );
    } on BffException catch (error) {
      return LocationRejected(
        error.code == 'no_match'
            ? LocationFailure.noMatch
            : LocationFailure.failed,
      );
    } on Exception {
      // A timeout or a platform failure reading the position.
      return const LocationRejected(LocationFailure.failed);
    }
  }
}
