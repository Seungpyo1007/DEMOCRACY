import 'package:democracy/src/core/account/account.dart';

/// Who holds the current session, as far as the auth service says. The
/// profile -- handle, consents -- comes from the BFF, not from here.
class AuthSession {
  const AuthSession({required this.userId, required this.provider, this.email});

  final String userId;
  final SignInProvider provider;
  final String? email;
}

/// Why a sign-in did not finish. Each has its own copy on the error screen.
enum AuthFailureKind {
  /// The person closed the provider's sheet. Not an error, but it ends here.
  cancelled,

  /// The network or the provider was unreachable.
  network,

  /// This email already belongs to an account made with another provider.
  linked,

  /// The account is suspended.
  disabled,

  /// The emailed code was wrong or has expired.
  invalidCode,

  /// Anything else; shown as the network copy with a retry.
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, {this.provider, this.detail});

  final AuthFailureKind kind;
  final SignInProvider? provider;
  final String? detail;

  @override
  String toString() => 'AuthFailure(${kind.name}, ${provider?.name}): $detail';
}

/// Signing in and holding the session. It knows providers and tokens and
/// nothing about the product: consent, handles and residency are the BFF's.
abstract interface class AuthRepository {
  /// The session kept from the last launch, refreshed if it can be.
  Future<AuthSession?> restore();

  /// Apple, Kakao or Google through the platform's own sheet.
  Future<AuthSession> signIn(SignInProvider provider);

  /// Emails a six-digit code. No password is ever made.
  Future<void> sendEmailCode(String email);

  Future<AuthSession> verifyEmailCode(String email, String code);

  /// The token the BFF client sends, or null when signed out.
  Future<String?> accessToken();

  Future<void> signOut();
}
