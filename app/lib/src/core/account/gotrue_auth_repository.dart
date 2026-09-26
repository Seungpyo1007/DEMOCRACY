import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_config.dart';
import 'package:democracy/src/core/account/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:gotrue/gotrue.dart' as gotrue;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Sessions from the Supabase auth service, with each provider's own
/// native sheet in front of it.
///
/// The `gotrue` client alone rather than `supabase_flutter`: the app reads
/// nothing from the database directly -- everything goes through the BFF --
/// so the realtime and storage clients would be dead weight, and a plain
/// object is easier to fake than a global singleton.
///
/// Every provider ends in `signInWithIdToken`, and email in a typed code, so
/// no redirect back into the app is ever needed.
class GoTrueAuthRepository implements AuthRepository {
  GoTrueAuthRepository({
    required Uri projectUrl,
    required String anonKey,
    required this.config,
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  }) : _client = gotrue.GoTrueClient(
         url: projectUrl.resolve('/auth/v1').toString(),
         headers: {'apikey': anonKey},
         // Implicit: the id-token and OTP flows never redirect, so there is
         // no PKCE verifier to keep between two launches.
         flowType: gotrue.AuthFlowType.implicit,
       ) {
    _client.onAuthStateChange.listen(_persist);
  }

  final AuthConfig config;
  final FlutterSecureStorage storage;
  final gotrue.GoTrueClient _client;

  static const _sessionKey = 'democracy.session.v1';

  bool _googleReady = false;
  bool _kakaoReady = false;

  @override
  Future<AuthSession?> restore() async {
    final raw = await storage.read(key: _sessionKey);
    if (raw == null) {
      return null;
    }
    try {
      final response = await _client.recoverSession(raw);
      return _sessionOf(response.user);
    } on gotrue.AuthRetryableFetchException {
      // Offline at launch: the stored session is still good; the token will
      // refresh on the next request that reaches the network.
      final session = _client.currentSession;
      return session == null ? null : _sessionOf(session.user);
    } on Object {
      // Revoked, expired past refresh, or written by an older build.
      await storage.delete(key: _sessionKey);
      return null;
    }
  }

  @override
  Future<AuthSession> signIn(SignInProvider provider) async {
    try {
      final gotrue.AuthResponse response;
      switch (provider) {
        case SignInProvider.apple:
          final rawNonce = _nonce();
          final credential = await SignInWithApple.getAppleIDCredential(
            // No name, no email scope: nothing on the "받지 않는 것" list is
            // asked for, even where the provider would hand it over.
            scopes: const [],
            nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
            webAuthenticationOptions:
                defaultTargetPlatform == TargetPlatform.iOS
                ? null
                : WebAuthenticationOptions(
                    clientId: config.appleServiceId,
                    redirectUri: Uri.parse(config.appleRedirectUri),
                  ),
          );
          response = await _client.signInWithIdToken(
            provider: gotrue.OAuthProvider.apple,
            idToken: _required(credential.identityToken, provider),
            nonce: rawNonce,
          );
        case SignInProvider.google:
          if (!_googleReady) {
            await GoogleSignIn.instance.initialize(
              clientId: config.googleIosClientId.isEmpty
                  ? null
                  : config.googleIosClientId,
              serverClientId: config.googleServerClientId,
            );
            _googleReady = true;
          }
          final account = await GoogleSignIn.instance.authenticate();
          response = await _client.signInWithIdToken(
            provider: gotrue.OAuthProvider.google,
            idToken: _required(account.authentication.idToken, provider),
          );
        case SignInProvider.kakao:
          if (!_kakaoReady) {
            await kakao.KakaoSdk.init(nativeAppKey: config.kakaoNativeKey);
            _kakaoReady = true;
          }
          // OIDC must be on in the Kakao app for an id token to come back.
          // The consent items it asks for are none: no profile, no phone.
          final token = await kakao.isKakaoTalkInstalled()
              ? await kakao.UserApi.instance.loginWithKakaoTalk()
              : await kakao.UserApi.instance.loginWithKakaoAccount();
          response = await _client.signInWithIdToken(
            provider: gotrue.OAuthProvider.kakao,
            idToken: _required(token.idToken, provider),
            accessToken: token.accessToken,
          );
        case SignInProvider.email:
          throw ArgumentError('Email signs in with a code, not a sheet.');
      }
      return _sessionOf(response.user, fallback: provider);
    } on Object catch (error) {
      throw _failure(error, provider);
    }
  }

  @override
  Future<void> sendEmailCode(String email) async {
    try {
      await _client.signInWithOtp(email: email, shouldCreateUser: true);
    } on Object catch (error) {
      throw _failure(error, SignInProvider.email);
    }
  }

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    try {
      final response = await _client.verifyOTP(
        email: email,
        token: code,
        type: gotrue.OtpType.email,
      );
      return _sessionOf(response.user, fallback: SignInProvider.email);
    } on Object catch (error) {
      throw _failure(error, SignInProvider.email);
    }
  }

  @override
  Future<String?> accessToken() async {
    final session = _client.currentSession;
    if (session == null) {
      return null;
    }
    if (session.isExpired) {
      try {
        await _client.refreshSession();
      } on Object {
        // Let the request go out with what there is; the BFF's 401 becomes
        // the "sign in again" sheet.
      }
    }
    return _client.currentSession?.accessToken;
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.signOut();
    } on Object {
      // Signing out locally must not depend on the network.
    }
    await storage.delete(key: _sessionKey);
  }

  Future<void> _persist(gotrue.AuthState event) async {
    final session = event.session;
    if (session == null) {
      await storage.delete(key: _sessionKey);
    } else {
      await storage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
    }
  }

  AuthSession _sessionOf(gotrue.User? user, {SignInProvider? fallback}) {
    if (user == null) {
      throw const AuthFailure(AuthFailureKind.unknown, detail: 'No user.');
    }
    final provider =
        SignInProvider.tryParse(user.appMetadata['provider']) ??
        fallback ??
        SignInProvider.email;
    return AuthSession(userId: user.id, provider: provider, email: user.email);
  }

  static String _required(String? token, SignInProvider provider) {
    if (token == null || token.isEmpty) {
      throw AuthFailure(
        AuthFailureKind.unknown,
        provider: provider,
        detail: 'The provider returned no id token.',
      );
    }
    return token;
  }

  static String _nonce() {
    final random = Random.secure();
    return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
  }

  static AuthFailure _failure(Object error, SignInProvider provider) {
    AuthFailure as(AuthFailureKind kind) =>
        AuthFailure(kind, provider: provider, detail: '$error');

    return switch (error) {
      final AuthFailure failure => failure,
      SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
      ) =>
        as(AuthFailureKind.cancelled),
      GoogleSignInException(code: GoogleSignInExceptionCode.canceled) => as(
        AuthFailureKind.cancelled,
      ),
      PlatformException(code: 'CANCELED') => as(AuthFailureKind.cancelled),
      gotrue.AuthRetryableFetchException() ||
      SocketException() ||
      TimeoutException() => as(AuthFailureKind.network),
      gotrue.AuthException(
        code: 'identity_already_exists' ||
            'email_exists' ||
            'user_already_exists',
      ) =>
        as(AuthFailureKind.linked),
      gotrue.AuthException(code: 'user_banned') => as(AuthFailureKind.disabled),
      gotrue.AuthException(code: 'otp_expired' || 'invalid_credentials') => as(
        AuthFailureKind.invalidCode,
      ),
      _ => as(AuthFailureKind.unknown),
    };
  }
}
