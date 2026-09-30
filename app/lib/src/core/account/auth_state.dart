import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_repository.dart';

/// Where the person is in signing in. Reading never depends on any of this;
/// only writing does.
sealed class AuthState {
  const AuthState();

  /// The signed-in account, when there is one with a profile.
  Account? get account => null;
}

/// The stored session is being read at launch.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.sessionExpired = false});

  /// Signed out because the server refused the session, not by choice.
  final bool sessionExpired;
}

/// A provider sheet is open.
final class AuthSigningIn extends AuthState {
  const AuthSigningIn(this.provider);

  final SignInProvider provider;
}

/// A code was emailed and is being waited for.
final class AuthAwaitingCode extends AuthState {
  const AuthAwaitingCode({required this.email, required this.sentAt});

  final String email;

  /// When the last code went out; resending waits a minute from here.
  final DateTime sentAt;
}

/// Signed in, but the consent screen has not been accepted, so there is no
/// profile yet. Nothing can be written from here.
final class AuthNeedsConsent extends AuthState {
  const AuthNeedsConsent({required this.session, required this.handleOptions});

  final AuthSession session;
  final List<String> handleOptions;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn({required this.account, this.residency});

  @override
  final Account account;

  final Residency? residency;

  AuthSignedIn copyWith({Account? account, Residency? residency}) =>
      AuthSignedIn(
        account: account ?? this.account,
        residency: residency ?? this.residency,
      );

  AuthSignedIn withoutResidency() => AuthSignedIn(account: account);
}

/// The person said they are under 14. The sign-in was deleted and no
/// account exists.
final class AuthUnder14 extends AuthState {
  const AuthUnder14();
}

/// The last attempt failed; the login screen shows why and lets them retry.
final class AuthFailed extends AuthState {
  const AuthFailed(this.failure);

  final AuthFailure failure;
}
