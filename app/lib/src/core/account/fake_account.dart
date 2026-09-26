import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/account_repository.dart';
import 'package:democracy/src/core/account/auth_repository.dart';

/// Sign-in without a network, for tests, goldens and a build without a BFF.
///
/// Every provider succeeds at once as the same sample person; [failNext]
/// makes the next attempt fail the way a real one would.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session});

  AuthSession? session;
  AuthFailureKind? failNext;

  /// The code the fake mailbox received.
  static const sampleCode = '481516';

  @override
  Future<AuthSession?> restore() async => session;

  @override
  Future<AuthSession> signIn(SignInProvider provider) async {
    _throwIfFailing(provider);
    return session = AuthSession(userId: 'sample-user', provider: provider);
  }

  @override
  Future<void> sendEmailCode(String email) async =>
      _throwIfFailing(SignInProvider.email);

  @override
  Future<AuthSession> verifyEmailCode(String email, String code) async {
    _throwIfFailing(SignInProvider.email);
    if (code != sampleCode) {
      throw const AuthFailure(
        AuthFailureKind.invalidCode,
        provider: SignInProvider.email,
      );
    }
    return session = AuthSession(
      userId: 'sample-user',
      provider: SignInProvider.email,
      email: email,
    );
  }

  @override
  Future<String?> accessToken() async => session == null ? null : 'sample';

  @override
  Future<void> signOut() async => session = null;

  void _throwIfFailing(SignInProvider provider) {
    final kind = failNext;
    if (kind != null) {
      failNext = null;
      throw AuthFailure(kind, provider: provider);
    }
  }
}

/// The account side kept in memory, following the same rules the server
/// enforces: offered handles only, 30 days between changes, required
/// consents, an address that is never kept.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.account,
    this.residency,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  Account? account;
  Residency? residency;
  final DateTime Function() _now;

  final _offered = <String>{};
  var _round = 0;

  static const _pool = [
    ['솔숲 27', '느티 41', '물길 08', '돌담 63', '산들 15'],
    ['조약돌 52', '너울 34', '들꽃 71', '갈대 19', '새벽별 86'],
  ];

  /// The district a fake address check lands in.
  static const sampleDistrict = (
    id: 'fixture-seoul-mapo-b',
    displayName: '서울 마포구 을',
  );

  @override
  Future<AccountSnapshot> me() async =>
      AccountSnapshot(account: account, residency: residency);

  @override
  Future<List<String>> handleOptions() async {
    final changed = account?.handleChangedAt;
    if (changed != null) {
      final allowed = changed.add(const Duration(days: 30));
      if (_now().isBefore(allowed)) {
        throw HandleTooSoonException(allowed);
      }
    }
    final options = _pool[_round++ % _pool.length];
    _offered.addAll(options);
    return options;
  }

  @override
  Future<AccountSnapshot> consent(ConsentInput input) async {
    if (!input.complete) {
      throw ArgumentError('age14, terms and privacy are required.');
    }
    _requireOffered(input.handle);
    account = Account(
      userId: 'sample-user',
      provider: SignInProvider.kakao,
      handle: input.handle,
      notify: input.notify,
    );
    return me();
  }

  @override
  Future<void> under14() async {
    account = null;
    residency = null;
  }

  @override
  Future<Account> claimHandle(String handle) async {
    final current = account!;
    final changed = current.handleChangedAt;
    if (changed != null) {
      final allowed = changed.add(const Duration(days: 30));
      if (_now().isBefore(allowed)) {
        throw HandleTooSoonException(allowed);
      }
    }
    _requireOffered(handle);
    return account = current.copyWith(
      handle: handle,
      handleChangedAt: _now().toUtc(),
    );
  }

  @override
  Future<Account> setNotify({required bool notify}) async =>
      account = account!.copyWith(notify: notify);

  @override
  Future<ResidencyGrant> verifyResidency({required String roadAddress}) async {
    final now = _now().toUtc();
    residency = Residency(
      districtId: sampleDistrict.id,
      displayName: sampleDistrict.displayName,
      verifiedAt: now,
      expiresAt: now.add(const Duration(days: 180)),
    );
    return ResidencyGrant(
      token: 'sample-residency-token',
      residency: residency!,
    );
  }

  @override
  Future<void> dropResidency() async => residency = null;

  @override
  Future<Map<String, Object?>> export() async => {
    'profile': {
      'handle': account?.handle,
      'provider': account?.provider.name,
      'notify': account?.notify,
    },
    'residency': residency == null
        ? null
        : {
            'districtId': residency!.districtId,
            'verifiedAt': residency!.verifiedAt.toIso8601String(),
          },
  };

  @override
  Future<void> delete({required bool deletePosts}) async {
    account = null;
    residency = null;
  }

  void _requireOffered(String handle) {
    if (!_offered.contains(handle)) {
      throw ArgumentError.value(handle, 'handle', 'was not offered');
    }
  }
}
