import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/account_repository.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_repository.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/account/fake_account.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 25, 3);
const _mapoB = DistrictRef(id: 'fixture-seoul-mapo-b', displayName: '서울 마포구 을');

class _ExpiringAccounts extends FakeAccountRepository {
  @override
  Future<AccountSnapshot> me() => Future.error(const SessionExpiredException());
}

({
  ProviderContainer container,
  FakeAuthRepository auth,
  FakeAccountRepository accounts,
})
_setUp({
  AuthSession? session,
  FakeAccountRepository? accounts,
  AddressState? address,
}) {
  final auth = FakeAuthRepository(session: session);
  final repo = accounts ?? FakeAccountRepository(now: () => _now);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      accountRepositoryProvider.overrideWithValue(repo),
      addressStoreProvider.overrideWithValue(InMemoryAddressStore(address)),
      clockProvider.overrideWithValue(
        FixedClock(KstInstant.fromDateTime(_now)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, accounts: repo);
}

Future<void> _consent(ProviderContainer c) async {
  final state = c.read(authControllerProvider) as AuthNeedsConsent;
  await c
      .read(authControllerProvider.notifier)
      .acceptConsent(
        ConsentInput(
          age14: true,
          terms: true,
          privacy: true,
          notify: false,
          handle: state.handleOptions.first,
        ),
      );
}

void main() {
  test('with no stored session, launch ends signed out', () async {
    final (:container, auth: _, accounts: _) = _setUp();

    await container.read(authRestoreProvider.future);

    expect(container.read(authControllerProvider), isA<AuthSignedOut>());
    expect(container.read(writeAccessProvider), WriteAccess.needsAccount);
  });

  test('a first sign-in asks for consent, then holds an account', () async {
    final (:container, auth: _, accounts: _) = _setUp();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(SignInProvider.kakao);
    final waiting = container.read(authControllerProvider);
    expect(waiting, isA<AuthNeedsConsent>());
    expect((waiting as AuthNeedsConsent).handleOptions, hasLength(5));

    await _consent(container);

    final signedIn = container.read(authControllerProvider) as AuthSignedIn;
    expect(signedIn.account.handle, '솔숲 27');
    expect(container.read(writeAccessProvider), WriteAccess.needsResidency);
  });

  test('a closed provider sheet ends as cancelled, not as an error', () async {
    final (:container, :auth, accounts: _) = _setUp();
    auth.failNext = AuthFailureKind.cancelled;

    await container
        .read(authControllerProvider.notifier)
        .signIn(SignInProvider.apple);

    final state = container.read(authControllerProvider) as AuthFailed;
    expect(state.failure.kind, AuthFailureKind.cancelled);
    expect(state.failure.provider, SignInProvider.apple);
  });

  test('a wrong email code stays on the code screen', () async {
    final (:container, auth: _, accounts: _) = _setUp();
    final controller = container.read(authControllerProvider.notifier);

    await controller.sendEmailCode('name@example.com');
    expect(container.read(authControllerProvider), isA<AuthAwaitingCode>());

    await expectLater(
      controller.verifyEmailCode('000000'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.invalidCode,
        ),
      ),
    );
    expect(container.read(authControllerProvider), isA<AuthAwaitingCode>());

    await controller.verifyEmailCode(FakeAuthRepository.sampleCode);
    expect(container.read(authControllerProvider), isA<AuthNeedsConsent>());
  });

  // Nothing about a child may be kept: the sign-in goes, no profile is made.
  test('under 14 deletes the sign-in and makes no account', () async {
    final (:container, :auth, :accounts) = _setUp();
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn(SignInProvider.google);

    await controller.declareUnder14();

    expect(container.read(authControllerProvider), isA<AuthUnder14>());
    expect(accounts.account, isNull);
    expect(await auth.accessToken(), isNull);
  });

  test(
    'a residency makes the district writable and binds to the account',
    () async {
      final (:container, auth: _, accounts: _) = _setUp(
        address: const AddressState.readOnly(district: _mapoB),
      );
      await container.read(addressRestoreProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      await controller.signIn(SignInProvider.kakao);
      await _consent(container);

      await controller.verifyResidency(roadAddress: '서울 마포구 신촌로 1');

      expect(container.read(writeAccessProvider), WriteAccess.allowed);
      final address = container.read(addressControllerProvider);
      expect(address.isVerified, isTrue);
      expect(address.verification!.userId, 'sample-user');
    },
  );

  test('signing out keeps the district and pauses the residency', () async {
    final (:container, auth: _, accounts: _) = _setUp(
      address: const AddressState.readOnly(district: _mapoB),
    );
    await container.read(addressRestoreProvider.future);
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn(SignInProvider.kakao);
    await _consent(container);
    await controller.verifyResidency(roadAddress: '서울 마포구 신촌로 1');

    await controller.signOut();

    final address = container.read(addressControllerProvider);
    expect(address.district?.id, _mapoB.id);
    expect(address.isVerified, isFalse);
    expect(container.read(writeAccessProvider), WriteAccess.needsAccount);
  });

  // A shared phone: the next person to sign in must not inherit a residency.
  test('a stored proof for another account is dropped on restore', () async {
    final accounts = FakeAccountRepository(now: () => _now)
      ..account = const Account(
        userId: 'sample-user',
        provider: SignInProvider.kakao,
        handle: '솔숲 27',
      );
    final (:container, auth: _, accounts: _) = _setUp(
      session: const AuthSession(
        userId: 'sample-user',
        provider: SignInProvider.kakao,
      ),
      accounts: accounts,
      address: AddressState.verified(
        district: _mapoB,
        proof: ResidencyVerificationProof(
          opaqueToken: 'someone-elses',
          verifiedAt: _now,
          userId: 'someone-else',
          expiresAt: _now.add(const Duration(days: 30)),
        ),
      ),
    );

    await container.read(authRestoreProvider.future);

    expect(container.read(addressControllerProvider).isVerified, isFalse);
    expect(container.read(writeAccessProvider), WriteAccess.needsResidency);
  });

  test(
    'the account residency is shown on a device that never saw the grant',
    () async {
      final accounts = FakeAccountRepository(now: () => _now)
        ..account = const Account(
          userId: 'sample-user',
          provider: SignInProvider.kakao,
          handle: '솔숲 27',
        )
        ..residency = Residency(
          districtId: _mapoB.id,
          displayName: _mapoB.displayName,
          verifiedAt: _now,
          expiresAt: _now.add(const Duration(days: 180)),
        );
      final (:container, auth: _, accounts: _) = _setUp(
        session: const AuthSession(
          userId: 'sample-user',
          provider: SignInProvider.kakao,
        ),
        accounts: accounts,
        address: const AddressState.readOnly(district: _mapoB),
      );

      await container.read(authRestoreProvider.future);

      expect(container.read(addressControllerProvider).isVerified, isTrue);
      expect(container.read(writeAccessProvider), WriteAccess.allowed);
    },
  );

  test('the handle cannot change twice inside 30 days', () async {
    final (:container, auth: _, accounts: _) = _setUp();
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn(SignInProvider.kakao);
    await _consent(container);

    final options = await controller.handleOptions();
    await controller.claimHandle(options.first);

    await expectLater(
      controller.handleOptions(),
      throwsA(isA<HandleTooSoonException>()),
    );
  });

  test('a refused session at launch signs out quietly', () async {
    final (:container, auth: _, accounts: _) = _setUp(
      session: const AuthSession(
        userId: 'sample-user',
        provider: SignInProvider.kakao,
      ),
      accounts: _ExpiringAccounts(),
    );

    await container.read(authRestoreProvider.future);

    final state = container.read(authControllerProvider) as AuthSignedOut;
    expect(state.sessionExpired, isFalse);
  });
}
