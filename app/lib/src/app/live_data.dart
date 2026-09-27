import 'package:democracy/src/core/account/account_repository.dart';
import 'package:democracy/src/core/account/auth_config.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/gotrue_auth_repository.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/bff_config.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/network/response_cache.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/remote_district_repository.dart';
import 'package:democracy/src/features/history/application/history_providers.dart';
import 'package:democracy/src/features/history/data/remote_history_repository.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/remote_address_repositories.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/data/remote_pledge_repository.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/remote_review_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

/// Every override a build with a BFF needs, or none without one.
///
/// Features with a live source read it. The rest -- AI and results -- are
/// still fixture-only, and a fixture keyed to a sample district has
/// nothing to say about a real one: they answer NotAvailableException, which
/// the screens show as 준비 중, rather than show sample candidates under a
/// real district's name.
List<Override> liveDataOverrides(BffConfig? config) {
  if (config == null) {
    return const [];
  }

  final authConfig = AuthConfig.fromEnvironment();
  final auth = GoTrueAuthRepository(
    // The BFF lives at <project>/functions/v1/bff; auth at <project>/auth/v1.
    projectUrl: config.baseUrl.replace(path: '/'),
    anonKey: config.anonKey,
    config: authConfig,
  );
  final client = BffClient.fromConfig(
    config,
    cache: SharedPreferencesResponseCache(),
    userToken: auth.accessToken,
  );
  return [
    authRepositoryProvider.overrideWithValue(auth),
    accountRepositoryProvider.overrideWithValue(
      RemoteAccountRepository(client),
    ),
    signInProvidersProvider.overrideWith(
      (ref) => authConfig.available(defaultTargetPlatform),
    ),
    districtRepositoryProvider.overrideWithValue(
      RemoteDistrictRepository(client),
    ),
    historyRepositoryProvider.overrideWithValue(
      RemoteHistoryRepository(client),
    ),
    pledgeRepositoryProvider.overrideWithValue(RemotePledgeRepository(client)),
    addressSearchRepositoryProvider.overrideWithValue(
      RemoteAddressSearchRepository(client),
    ),
    locationRepositoryProvider.overrideWithValue(
      RemoteLocationRepository(client),
    ),
    matchRepositoryProvider.overrideWithValue(const _UnavailableMatch()),
    directionRepositoryProvider.overrideWithValue(
      const _UnavailableDirection(),
    ),
    resultsRepositoryProvider.overrideWithValue(const _UnavailableResults()),
    reviewRepositoryProvider.overrideWithValue(RemoteReviewRepository(client)),
    communityRepositoryProvider.overrideWithValue(
      RemoteCommunityRepository(client),
    ),
    addressStoreProvider.overrideWith(
      (ref) => LiveAddressStore(const SecureAddressStore()),
    ),
  ];
}

/// Forgets a district saved while the app ran on fixtures, and a residency
/// that no account stands behind.
///
/// A fixture id means nothing to the BFF, so restoring one would open on an
/// empty home. Sending the resident back to onboarding once is the honest
/// outcome.
class LiveAddressStore implements AddressStore {
  const LiveAddressStore(this.inner);

  final AddressStore inner;

  @override
  Future<AddressState?> read() async {
    final stored = await inner.read();
    final id = stored?.district?.id;
    if (id != null && id.startsWith('fixture-')) {
      await inner.clear();
      return null;
    }
    // A residency with no account behind it was made by a build without
    // accounts; here residency belongs to an account, so it is read-only.
    if (stored != null &&
        stored.isVerified &&
        stored.verification?.userId == null) {
      final downgraded = AddressState.readOnly(district: stored.district);
      await inner.write(downgraded);
      return downgraded;
    }
    return stored;
  }

  @override
  Future<void> write(AddressState state) => inner.write(state);

  @override
  Future<void> clear() => inner.clear();
}

class _UnavailableMatch implements MatchRepository {
  const _UnavailableMatch();

  @override
  Future<MatchReport> loadReport(String districtId) =>
      Future.error(const NotAvailableException('ai match'));

  @override
  Stream<String> streamReasoning(String districtId, String candidateId) =>
      Stream.error(const NotAvailableException('ai reasoning'));
}

class _UnavailableDirection implements DirectionRepository {
  const _UnavailableDirection();

  @override
  Future<DirectionReport> loadReport(String districtId) =>
      Future.error(const NotAvailableException('ai direction'));
}

class _UnavailableResults implements ResultsRepository {
  const _UnavailableResults();

  @override
  Stream<RawElectionResults> watch(String districtId) =>
      Stream.error(const NotAvailableException('results'));
}
