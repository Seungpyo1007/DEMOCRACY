/// How a person signed in. Deliberately no phone and no real-name check:
/// docs/ELECTION_LAW.md -- the 실명확인 duty was struck down in 2021, and
/// collecting it anyway would be personal data with no legal reason.
enum SignInProvider {
  apple('Apple'),
  kakao('카카오'),
  google('Google'),
  email('이메일');

  const SignInProvider(this.label);

  final String label;

  static SignInProvider? tryParse(Object? name) {
    for (final provider in values) {
      if (provider.name == name) {
        return provider;
      }
    }
    return null;
  }
}

/// The signed-in person as the BFF knows them.
///
/// Everything here is on the consent screen's "받는 것" list and nothing
/// else: no name, no phone, no birth date, no address.
class Account {
  const Account({
    required this.userId,
    required this.provider,
    required this.handle,
    this.email,
    this.handleChangedAt,
    this.notify = false,
  });

  factory Account.fromJson(Map<String, Object?> json) {
    final userId = json['userId'];
    final handle = json['handle'];
    final provider = SignInProvider.tryParse(json['provider']);
    if (userId is! String || handle is! String || provider == null) {
      throw const FormatException('An account needs userId, handle, provider.');
    }
    return Account(
      userId: userId,
      provider: provider,
      handle: handle,
      email: json['email'] as String?,
      handleChangedAt: _time(json['handleChangedAt']),
      notify: json['notify'] == true,
    );
  }

  final String userId;
  final SignInProvider provider;

  /// A generated pseudonym like `솔숲 27`. Shown only on posts made under
  /// the handle; anonymous posting stays the default.
  final String handle;

  /// Present only when the provider gave one.
  final String? email;
  final DateTime? handleChangedAt;
  final bool notify;

  Account copyWith({String? handle, DateTime? handleChangedAt, bool? notify}) {
    return Account(
      userId: userId,
      provider: provider,
      email: email,
      handle: handle ?? this.handle,
      handleChangedAt: handleChangedAt ?? this.handleChangedAt,
      notify: notify ?? this.notify,
    );
  }
}

/// A residency record: which district, when, until when. It never holds the
/// address it was derived from -- the server discards that on the spot.
class Residency {
  const Residency({
    required this.districtId,
    required this.displayName,
    required this.verifiedAt,
    required this.expiresAt,
  });

  factory Residency.fromJson(Map<String, Object?> json) {
    final districtId = json['districtId'];
    final verifiedAt = _time(json['verifiedAt']);
    final expiresAt = _time(json['expiresAt']);
    if (districtId is! String || verifiedAt == null || expiresAt == null) {
      throw const FormatException(
        'A residency needs districtId, verifiedAt, expiresAt.',
      );
    }
    return Residency(
      districtId: districtId,
      displayName: json['displayName'] as String? ?? districtId,
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
    );
  }

  final String districtId;
  final String displayName;
  final DateTime verifiedAt;
  final DateTime expiresAt;

  bool isValidAt(DateTime now) => now.toUtc().isBefore(expiresAt);
}

/// A freshly issued residency: the record plus the bearer token the server
/// handed back once. Only the token's hash is kept on the server.
class ResidencyGrant {
  const ResidencyGrant({required this.token, required this.residency});

  factory ResidencyGrant.fromJson(Map<String, Object?> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('A residency grant needs a token.');
    }
    return ResidencyGrant(token: token, residency: Residency.fromJson(json));
  }

  final String token;
  final Residency residency;
}

/// `GET /me`: no account yet means the person signed in but has not
/// accepted the consent screen.
class AccountSnapshot {
  const AccountSnapshot({this.account, this.residency});

  factory AccountSnapshot.fromJson(Map<String, Object?> json) {
    final profile = json['profile'];
    final residency = json['residency'];
    return AccountSnapshot(
      account: profile is Map<String, Object?>
          ? Account.fromJson(profile)
          : null,
      residency: residency is Map<String, Object?>
          ? Residency.fromJson(residency)
          : null,
    );
  }

  final Account? account;
  final Residency? residency;
}

/// What the consent screen sends. The three required ones must be true; the
/// server refuses otherwise.
class ConsentInput {
  const ConsentInput({
    required this.age14,
    required this.terms,
    required this.privacy,
    required this.notify,
    required this.handle,
  });

  final bool age14;
  final bool terms;
  final bool privacy;
  final bool notify;
  final String handle;

  bool get complete => age14 && terms && privacy;

  Map<String, Object?> toJson() => {
    'age14': age14,
    'terms': terms,
    'privacy': privacy,
    'notify': notify,
    'handle': handle,
  };
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
