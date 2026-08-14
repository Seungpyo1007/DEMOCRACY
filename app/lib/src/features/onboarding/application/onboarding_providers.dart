import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/features/onboarding/data/fake_address_repositories.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in tests and, later, wherever the real client is wired.
final addressSearchRepositoryProvider = Provider<AddressSearchRepository>(
  (ref) => const FakeAddressSearchRepository(),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => const FakeLocationRepository(),
);

/// What the resident said about themselves, kept past onboarding.
///
/// The AI screen reads this, so it outlives the flow that fills it in.
final residentProfileProvider =
    NotifierProvider<ResidentProfileController, ResidentProfile>(
      ResidentProfileController.new,
    );

class ResidentProfileController extends Notifier<ResidentProfile> {
  @override
  ResidentProfile build() => const ResidentProfile();

  void toggleTag(String tag) => state = state.toggle(tag);

  void setInterest(int value) => state = state.withInterest(value);
}

/// The three steps the guide names.
enum OnboardingStep { address, profile, done }

/// Everything the flow holds while it runs.
///
/// Kept apart from [AddressState]: that is the app-wide verification gate and
/// must not gain fields that only matter while onboarding is open.
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.address,
    this.query = '',
    this.district,
    this.locationFailure,
    this.detecting = false,
  });

  final OnboardingStep step;
  final String query;

  /// Null until the resident picks a result or the device resolves one.
  final DistrictRef? district;

  /// Set when a location attempt was refused or failed. Never blocks: the
  /// manual field stays available and this is shown beside it.
  final LocationFailure? locationFailure;

  final bool detecting;

  bool get canAdvance => district != null;

  double get progress => switch (step) {
    OnboardingStep.address => 1 / 3,
    OnboardingStep.profile => 2 / 3,
    OnboardingStep.done => 1,
  };

  int get stepNumber => switch (step) {
    OnboardingStep.address => 1,
    OnboardingStep.profile => 2,
    OnboardingStep.done => 3,
  };

  OnboardingState copyWith({
    OnboardingStep? step,
    String? query,
    DistrictRef? district,
    LocationFailure? locationFailure,
    bool clearLocationFailure = false,
    bool? detecting,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      query: query ?? this.query,
      district: district ?? this.district,
      locationFailure: clearLocationFailure
          ? null
          : (locationFailure ?? this.locationFailure),
      detecting: detecting ?? this.detecting,
    );
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void selectDistrict(DistrictRef district, {String? address}) {
    state = state.copyWith(
      district: district,
      query: address ?? state.query,
      clearLocationFailure: true,
    );
  }

  Future<void> detectLocation() async {
    state = state.copyWith(detecting: true, clearLocationFailure: true);

    final result = await ref.read(locationRepositoryProvider).detectDistrict();

    state = switch (result) {
      LocationResolved(:final district) => state.copyWith(
        district: district,
        detecting: false,
        clearLocationFailure: true,
      ),
      LocationRejected(:final failure) => state.copyWith(
        detecting: false,
        locationFailure: failure,
      ),
    };
  }

  void next() {
    state = switch (state.step) {
      OnboardingStep.address when state.canAdvance => state.copyWith(
        step: OnboardingStep.profile,
      ),
      OnboardingStep.address => state,
      OnboardingStep.profile => state.copyWith(step: OnboardingStep.done),
      OnboardingStep.done => state,
    };
  }

  /// True when there was somewhere to go back to.
  bool back() {
    switch (state.step) {
      case OnboardingStep.address:
        return false;
      case OnboardingStep.profile:
        state = state.copyWith(step: OnboardingStep.address);
        return true;
      case OnboardingStep.done:
        state = state.copyWith(step: OnboardingStep.profile);
        return true;
    }
  }
}
