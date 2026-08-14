import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';

/// Address lookup over the bundled sample list.
///
/// The real one is a road-name/Kakao query behind the BFF. Matching is a
/// substring test on purpose: the point of this stand-in is to exercise the
/// screen's empty, single and multiple states, not to imitate a ranker.
class FakeAddressSearchRepository implements AddressSearchRepository {
  const FakeAddressSearchRepository({this.loader = const FixtureLoader()});

  final FixtureLoader loader;

  @override
  Future<List<AddressSuggestion>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final payload = await loader.load('address_suggestions');
    final raw = payload['suggestions'];
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, Object?>>()
        .map(AddressSuggestion.fromJson)
        .where(
          (suggestion) =>
              suggestion.address.contains(trimmed) ||
              suggestion.district.displayName.contains(trimmed),
        )
        .toList(growable: false);
  }
}

/// Stands in for geolocator plus reverse geocoding.
///
/// [outcome] is injectable because the denial paths are the ones worth
/// building carefully -- the guide requires a manual fallback, and a fake that
/// only ever succeeds would leave that fallback undrawn and untested.
class FakeLocationRepository implements LocationRepository {
  const FakeLocationRepository({
    this.outcome,
    this.loader = const FixtureLoader(),
  });

  final LocationFailure? outcome;
  final FixtureLoader loader;

  @override
  Future<LocationResult> detectDistrict() async {
    if (outcome != null) {
      return LocationRejected(outcome!);
    }

    final payload = await loader.load('address_suggestions');
    final raw = payload['suggestions'];
    if (raw is! List || raw.isEmpty) {
      return const LocationRejected(LocationFailure.noMatch);
    }

    final first = AddressSuggestion.fromJson(
      raw.whereType<Map<String, Object?>>().first,
    );
    return LocationResolved(first.district);
  }
}
