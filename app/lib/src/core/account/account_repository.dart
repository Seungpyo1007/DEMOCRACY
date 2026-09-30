import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/network/bff_client.dart';

/// The handle was changed less than 30 days ago.
class HandleTooSoonException implements Exception {
  const HandleTooSoonException(this.availableAt);

  /// When a change is allowed again, if the server said.
  final DateTime? availableAt;
}

/// The account side of the BFF: consent, handle, residency, export, deletion.
/// Every call is made as the signed-in person; none is cached.
abstract interface class AccountRepository {
  Future<AccountSnapshot> me();

  /// Five generated handles. Only an offered handle can be claimed, so
  /// nobody can type a candidate's name into one.
  Future<List<String>> handleOptions();

  Future<AccountSnapshot> consent(ConsentInput input);

  /// Deletes the just-created sign-in. No profile was ever made.
  Future<void> under14();

  /// Throws [HandleTooSoonException] inside the 30-day limit.
  Future<Account> claimHandle(String handle);

  Future<Account> setNotify({required bool notify});

  /// The server re-derives the district from the address and forgets the
  /// address. The client drops it too as soon as this returns.
  Future<ResidencyGrant> verifyResidency({required String roadAddress});

  Future<void> dropResidency();

  /// Everything the server holds about this person, as sent.
  Future<Map<String, Object?>> export();

  /// Deletes the account. With [deletePosts] off, posts stay under
  /// 「탈퇴한 주민」 with no link back.
  Future<void> delete({required bool deletePosts});
}

class RemoteAccountRepository implements AccountRepository {
  const RemoteAccountRepository(this.client);

  final BffClient client;

  @override
  Future<AccountSnapshot> me() async =>
      AccountSnapshot.fromJson((await client.get('/me')).data);

  @override
  Future<List<String>> handleOptions() => _tooSoonAware(() async {
    final data = (await client.get('/me/handle/options')).data;
    final handles = data['handles'];
    if (handles is! List) {
      throw const FormatException('Handle options need a list.');
    }
    return handles.whereType<String>().toList(growable: false);
  });

  @override
  Future<AccountSnapshot> consent(ConsentInput input) async =>
      AccountSnapshot.fromJson(
        (await client.post('/me/consent', body: input.toJson())).data,
      );

  @override
  Future<void> under14() => client.post('/me/under14');

  @override
  Future<Account> claimHandle(String handle) => _tooSoonAware(() async {
    final data = (await client.post(
      '/me/handle',
      body: {'handle': handle},
    )).data;
    return Account.fromJson(_profileOf(data));
  });

  /// The 30-day limit arrives as `too_soon` with `availableAt` beside it.
  static Future<T> _tooSoonAware<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BffException catch (error) {
      if (error.code == 'too_soon') {
        final at = error.details['availableAt'];
        throw HandleTooSoonException(
          at is String ? DateTime.tryParse(at)?.toUtc() : null,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Account> setNotify({required bool notify}) async {
    final data = (await client.patch('/me', body: {'notify': notify})).data;
    return Account.fromJson(_profileOf(data));
  }

  @override
  Future<ResidencyGrant> verifyResidency({required String roadAddress}) async =>
      ResidencyGrant.fromJson(
        (await client.post(
          '/residency/verify',
          body: {'roadAddress': roadAddress},
        )).data,
      );

  @override
  Future<void> dropResidency() => client.delete('/residency');

  @override
  Future<Map<String, Object?>> export() async =>
      (await client.get('/me/export')).data;

  @override
  Future<void> delete({required bool deletePosts}) =>
      client.delete('/me', query: {'posts': deletePosts ? 'delete' : 'keep'});

  static Map<String, Object?> _profileOf(Map<String, Object?> data) {
    final profile = data['profile'];
    return profile is Map<String, Object?> ? profile : data;
  }
}
