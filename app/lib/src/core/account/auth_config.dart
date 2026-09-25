import 'package:democracy/src/core/account/account.dart';
import 'package:flutter/foundation.dart';

/// Provider keys, read from `--dart-define` like the BFF's.
///
/// None of them is a secret -- a native app key and OAuth client ids ship in
/// every build -- but they differ per environment, so they come from the
/// build rather than the source. A provider whose keys are missing is not
/// offered: a button that can only fail is worse than no button.
class AuthConfig {
  const AuthConfig({
    this.kakaoNativeKey = '',
    this.googleIosClientId = '',
    this.googleServerClientId = '',
    this.appleServiceId = '',
    this.appleRedirectUri = '',
  });

  factory AuthConfig.fromEnvironment() => const AuthConfig(
    kakaoNativeKey: String.fromEnvironment('KAKAO_NATIVE_KEY'),
    googleIosClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    appleServiceId: String.fromEnvironment('APPLE_SERVICE_ID'),
    appleRedirectUri: String.fromEnvironment('APPLE_REDIRECT_URI'),
  );

  final String kakaoNativeKey;
  final String googleIosClientId;

  /// The web client id; Google puts it in the id token's audience, which is
  /// what the auth service checks.
  final String googleServerClientId;

  /// Apple outside iOS signs in through a web page, which needs a Services ID
  /// and a redirect the auth service answers.
  final String appleServiceId;
  final String appleRedirectUri;

  /// The providers this build can actually complete, in the platform's order:
  /// Apple first on iOS, Google first on Android. Email always works.
  List<SignInProvider> available(TargetPlatform platform) {
    final ios = platform == TargetPlatform.iOS;
    final apple =
        ios || (appleServiceId.isNotEmpty && appleRedirectUri.isNotEmpty);
    final google =
        googleServerClientId.isNotEmpty &&
        (!ios || googleIosClientId.isNotEmpty);
    final kakao = kakaoNativeKey.isNotEmpty;
    final order = ios
        ? [SignInProvider.apple, SignInProvider.kakao, SignInProvider.google]
        : [SignInProvider.google, SignInProvider.kakao, SignInProvider.apple];
    return [
      for (final provider in order)
        if (switch (provider) {
          SignInProvider.apple => apple,
          SignInProvider.kakao => kakao,
          SignInProvider.google => google,
          SignInProvider.email => false,
        })
          provider,
      SignInProvider.email,
    ];
  }
}
