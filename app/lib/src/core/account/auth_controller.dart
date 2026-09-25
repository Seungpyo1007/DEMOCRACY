import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/account_repository.dart';
import 'package:democracy/src/core/account/auth_repository.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/account/fake_account.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fakes by default, so tests, goldens and a build without a BFF sign in
/// offline. `liveDataOverrides` swaps in the real ones.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FakeAuthRepository(),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => FakeAccountRepository(),
);

/// The providers the login screen offers, in the platform's order. Without
/// a BFF every one is shown, so the screen can be seen whole.
final signInProvidersProvider = Provider<List<SignInProvider>>((ref) {
  return defaultTargetPlatform == TargetPlatform.iOS
      ? const [
          SignInProvider.apple,
          SignInProvider.kakao,
          SignInProvider.google,
          SignInProvider.email,
        ]
      : const [
          SignInProvider.google,
          SignInProvider.kakao,
          SignInProvider.apple,
          SignInProvider.email,
        ];
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Reads the stored session once at launch. It waits for the address
/// restore because it may correct what that restored: a residency that
/// belongs to someone else, or that has expired, goes back to read-only.
final authRestoreProvider = FutureProvider<void>((ref) async {
  await ref.watch(addressRestoreProvider.future);
  await ref.read(authControllerProvider.notifier).restore();
});

/// What stands between the reader and writing in the current district.
enum WriteAccess {
  /// Nobody is signed in, or the consent screen is not done.
  needsAccount,

  /// Signed in, with no current residency in this district.
  needsResidency,

  allowed,
}

final writeAccessProvider = Provider<WriteAccess>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthSignedIn) {
    return WriteAccess.needsAccount;
  }
  final residency = auth.residency;
  final district = ref.watch(districtProvider);
  final now = ref.watch(clockProvider).now().utc;
  if (residency == null ||
      !residency.isValidAt(now) ||
      residency.districtId != district?.id) {
    return WriteAccess.needsResidency;
  }
  return WriteAccess.allowed;
});

class AuthController extends Notifier<AuthState> {
  AuthRepository get _auth => ref.read(authRepositoryProvider);
  AccountRepository get _accounts => ref.read(accountRepositoryProvider);

  @override
  AuthState build() => const AuthRestoring();

  Future<void> restore() async {
    final session = await _auth.restore();
    if (session == null) {
      state = const AuthSignedOut();
      return;
    }
    await _afterSession(session, restoring: true);
  }

  Future<void> signIn(SignInProvider provider) async {
    state = AuthSigningIn(provider);
    try {
      await _afterSession(await _auth.signIn(provider));
    } on AuthFailure catch (failure) {
      state = AuthFailed(failure);
    }
  }

  Future<void> sendEmailCode(String email) async {
    try {
      await _auth.sendEmailCode(email);
      state = AuthAwaitingCode(email: email, sentAt: _now());
    } on AuthFailure catch (failure) {
      state = AuthFailed(failure);
    }
  }

  /// Throws [AuthFailure] with [AuthFailureKind.invalidCode] and stays on the
  /// code screen when the code is wrong; any other failure ends the attempt.
  Future<void> verifyEmailCode(String code) async {
    final waiting = state;
    if (waiting is! AuthAwaitingCode) {
      return;
    }
    try {
      await _afterSession(await _auth.verifyEmailCode(waiting.email, code));
    } on AuthFailure catch (failure) {
      if (failure.kind == AuthFailureKind.invalidCode) {
        rethrow;
      }
      state = AuthFailed(failure);
    }
  }

  Future<void> rerollHandles() async {
    final waiting = state;
    if (waiting is! AuthNeedsConsent) {
      return;
    }
    state = AuthNeedsConsent(
      session: waiting.session,
      handleOptions: await _accounts.handleOptions(),
    );
  }

  Future<void> acceptConsent(ConsentInput input) async {
    final snapshot = await _guard(() => _accounts.consent(input));
    _adopt(snapshot);
  }

  /// Deletes the sign-in that was just made. Nothing about this person is
  /// kept: no profile existed, and the auth record goes too.
  Future<void> declareUnder14() async {
    await _guard(_accounts.under14);
    await _auth.signOut();
    state = const AuthUnder14();
  }

  Future<void> claimHandle(String handle) async {
    final signedIn = _signedIn;
    final account = await _guard(() => _accounts.claimHandle(handle));
    state = signedIn.copyWith(account: account);
  }

  Future<List<String>> handleOptions() => _guard(_accounts.handleOptions);

  Future<void> setNotify({required bool notify}) async {
    final signedIn = _signedIn;
    final account = await _guard(() => _accounts.setNotify(notify: notify));
    state = signedIn.copyWith(account: account);
  }

  /// Checks the address against the district map and records residency. The
  /// address is passed through and forgotten; only the grant is kept.
  Future<Residency> verifyResidency({required String roadAddress}) async {
    final signedIn = _signedIn;
    final grant = await _guard(
      () => _accounts.verifyResidency(roadAddress: roadAddress),
    );
    state = signedIn.copyWith(residency: grant.residency);
    ref
        .read(addressControllerProvider.notifier)
        .adoptResidency(grant, userId: signedIn.account.userId);
    return grant.residency;
  }

  Future<void> dropResidency() async {
    final signedIn = _signedIn;
    await _guard(_accounts.dropResidency);
    state = signedIn.withoutResidency();
    ref.read(addressControllerProvider.notifier).dropResidency();
  }

  Future<Map<String, Object?>> export() => _guard(_accounts.export);

  /// Signs out on this device. The district stays, so reading goes on; the
  /// residency pauses and comes back with the next sign-in.
  Future<void> signOut() async {
    await _auth.signOut();
    state = const AuthSignedOut();
    ref.read(addressControllerProvider.notifier).dropResidency();
  }

  Future<void> deleteAccount({required bool deletePosts}) async {
    await _guard(() => _accounts.delete(deletePosts: deletePosts));
    await _auth.signOut();
    state = const AuthSignedOut();
    ref.read(addressControllerProvider.notifier).dropResidency();
  }

  /// Back to the login screen's resting state after a failure was shown.
  void dismissFailure() {
    if (state is AuthFailed || state is AuthUnder14) {
      state = const AuthSignedOut();
    }
  }

  Future<void> _afterSession(
    AuthSession session, {
    bool restoring = false,
  }) async {
    final AccountSnapshot snapshot;
    try {
      snapshot = await _accounts.me();
    } on SessionExpiredException {
      await _auth.signOut();
      state = AuthSignedOut(sessionExpired: !restoring);
      return;
    } on BffException {
      // Offline at launch with a stored session: stay signed out for writing
      // rather than guess at a profile; the next launch or retry resolves it.
      state = const AuthSignedOut();
      return;
    }

    final account = snapshot.account;
    if (account == null) {
      state = AuthNeedsConsent(
        session: session,
        handleOptions: await _accounts.handleOptions(),
      );
      return;
    }
    _adopt(snapshot);
  }

  void _adopt(AccountSnapshot snapshot) {
    final account = snapshot.account!;
    state = AuthSignedIn(account: account, residency: snapshot.residency);
    ref
        .read(addressControllerProvider.notifier)
        .reconcileResidency(
          userId: account.userId,
          residency: snapshot.residency,
          now: _now(),
        );
  }

  AuthSignedIn get _signedIn {
    final current = state;
    if (current is! AuthSignedIn) {
      throw StateError('Not signed in.');
    }
    return current;
  }

  /// Runs an account call; a refused session signs out with the expiry flag,
  /// which the app answers with the "sign in again" sheet.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SessionExpiredException {
      await _auth.signOut();
      state = const AuthSignedOut(sessionExpired: true);
      ref.read(addressControllerProvider.notifier).dropResidency();
      rethrow;
    }
  }

  DateTime _now() => ref.read(clockProvider).now().utc;
}
