import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/reviews/data/remote_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/community_write_failure.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_bff.dart';
import '../../support/fake_channel_transport.dart';

/// The fixtures are the contract the BFF's community routes are written to
/// (server/supabase/functions/bff/contract.ts checks them too).
Map<String, Object?> fixture(String name) {
  final decoded =
      json.decode(File('assets/fixtures/$name.json').readAsStringSync())
          as Map<String, Object?>;
  return decoded..remove('_note');
}

Map<String, Object?> errorWith(String code, [Map<String, Object?>? extra]) => {
  'servedAt': '2026-09-24T03:00:00Z',
  'error': {...?extra, 'code': code, 'message': code},
};

const _id = 'nec-24863648';
const _reviews = '/districts/$_id/reviews';
const _community = '/districts/$_id/community';
const _messages = '/districts/$_id/messages';

ReviewDraft _complete({bool anonymous = true}) {
  var draft = const ReviewDraft().withBody('회의록과 예산서를 대조해 보았습니다.');
  for (final (i, axis) in ReviewDraft.axes.indexed) {
    draft = draft.withScore(axis, i + 2);
  }
  return draft.withAnonymous(anonymous);
}

void main() {
  group('reviews', () {
    test('the fixture is a valid board response', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            _reviews: (
              status: 200,
              body: envelope(fixture('reviews_fixture-seoul-mapo-b')),
            ),
          }),
        ),
      );

      final board = await repo.loadBoard(_id);

      expect(board.summary.respondents, 412);
      expect(board.summary.isEmpty, isFalse);
      expect(board.reviews, isNotEmpty);
    });

    // A live district starts with no reviews; that must parse, and say so.
    test('a district with no reviews yet is an empty board', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            _reviews: (
              status: 200,
              body: envelope({
                'summary': {'average': 0, 'respondents': 0, 'axes': <Object>[]},
                'reviews': <Object>[],
              }),
            ),
          }),
        ),
      );

      final board = await repo.loadBoard(_id);

      expect(board.summary.isEmpty, isTrue);
      expect(board.reviews, isEmpty);
    });

    test('posts the axes, the body and the anonymous choice', () async {
      final adapter = FakeBffAdapter({
        'POST $_reviews': (
          status: 200,
          body: envelope(fixture('reviews_fixture-seoul-mapo-b')),
        ),
      });
      final repo = RemoteReviewRepository(
        fakeBffClient(adapter, userToken: () async => 'user-jwt'),
      );

      await repo.submit(_id, _complete());

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.headers['Authorization'], 'Bearer user-jwt');
      expect(json.decode(sent.data as String), {
        'scores': {'소통': 2, '공약이행': 3, '지역발전': 4, '도덕성': 5},
        'body': '회의록과 예산서를 대조해 보았습니다.',
        'anonymous': true,
      });
    });

    test('a missing residency says so and asks to verify again', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            'POST $_reviews': (
              status: 403,
              body: errorWith('residency_required'),
            ),
          }),
          userToken: () async => 'user-jwt',
        ),
      );

      await expectLater(
        repo.submit(_id, _complete()),
        throwsA(
          isA<CommunityWriteException>()
              .having((e) => e.residencyLost, 'residencyLost', isTrue)
              .having((e) => e.message, 'message', contains('주민 인증')),
        ),
      );
    });

    test('refused wording comes back as the same hard stop', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            'POST $_reviews': (
              status: 422,
              body: errorWith('content_rejected', {'reason': 'hate'}),
            ),
          }),
          userToken: () async => 'user-jwt',
        ),
      );

      await expectLater(
        repo.submit(_id, _complete()),
        throwsA(
          isA<CommunityWriteException>().having(
            (e) => e.warning,
            'warning',
            ContentWarning.hate,
          ),
        ),
      );
    });

    test('too many posts says when to try again', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            'POST $_reviews': (status: 429, body: errorWith('rate_limited')),
          }),
          userToken: () async => 'user-jwt',
        ),
      );

      await expectLater(
        repo.submit(_id, _complete()),
        throwsA(
          isA<CommunityWriteException>().having(
            (e) => e.message,
            'message',
            contains('1분'),
          ),
        ),
      );
    });

    // Not a write failure: the app answers it with the sign-in-again sheet.
    test('a refused session passes through as SessionExpired', () async {
      final repo = RemoteReviewRepository(
        fakeBffClient(
          FakeBffAdapter({
            'POST $_reviews': (status: 401, body: errorWith('unauthorized')),
          }),
          userToken: () async => 'expired-jwt',
        ),
      );

      await expectLater(
        repo.submit(_id, _complete()),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('community', () {
    test('the fixture is a valid channel and thread response', () async {
      final repo = RemoteCommunityRepository(
        fakeBffClient(
          FakeBffAdapter({
            _community: (
              status: 200,
              body: envelope(fixture('community_fixture-seoul-mapo-b')),
            ),
          }),
        ),
      );

      final messages = await repo.watchChannel(_id).first;
      final threads = await repo.loadThreads(_id);

      expect(messages, hasLength(3));
      expect(messages.first.mine, isFalse);
      expect(threads.first.origin, '법안 발의로 자동 생성');
    });

    test('marks the reader\'s own messages as the server says', () async {
      final repo = RemoteCommunityRepository(
        fakeBffClient(
          FakeBffAdapter({
            _community: (
              status: 200,
              body: envelope({
                'messages': [
                  {
                    'id': 'm1',
                    'author': '익명 주민',
                    'body': '안녕하세요',
                    'verifiedResident': true,
                    'mine': true,
                  },
                ],
                'threads': <Object>[],
              }),
            ),
          }),
        ),
      );

      final messages = await repo.watchChannel(_id).first;

      expect(messages.single.mine, isTrue);
      expect(await repo.loadThreads(_id), isEmpty);
    });

    test('sending posts anonymously, shows the message at once, then reads '
        'again without a socket', () async {
      final channel = fixture('community_fixture-seoul-mapo-b');
      final sent = {
        'id': 'm9',
        'author': '익명 주민',
        'body': '안녕',
        'verifiedResident': true,
        'mine': true,
        'createdAt': '2026-09-24T03:00:00.000Z',
      };
      final adapter = FakeBffAdapter({
        _community: (status: 200, body: envelope(channel)),
        'POST $_messages': (status: 200, body: envelope({'message': sent})),
      });
      final repo = RemoteCommunityRepository(
        fakeBffClient(adapter, userToken: () async => 'user-jwt'),
      );

      final seen = <List<ChatMessage>>[];
      final subscription = repo.watchChannel(_id).listen(seen.add);
      await pumpEventQueue();

      // The server has it from here on.
      adapter.routes[_community] = (
        status: 200,
        body: envelope({
          ...channel,
          'messages': [...channel['messages']! as List, sent],
        }),
      );
      await repo.send(_id, '  안녕  ');
      await pumpEventQueue();
      await subscription.cancel();

      final post = adapter.requests.firstWhere((r) => r.method == 'POST');
      expect(json.decode(post.data as String), {
        'body': '안녕',
        'anonymous': true,
      });
      // The read on opening, then the POST's answer; the read after the send
      // agrees, so it is not shown again.
      expect(seen.map((m) => m.length), [3, 4]);
      expect(seen.last.last.mine, isTrue);
      expect(adapter.requests.where((r) => r.method == 'GET'), hasLength(2));
    });

    test('live: one\'s own message shows once, from the POST and the socket, '
        'with no read after sending', () async {
      final channel = fixture('community_fixture-seoul-mapo-b');
      final sent = {
        'id': 'm9',
        'author': '익명 주민',
        'body': '안녕',
        'verifiedResident': true,
        'mine': true,
        'createdAt': '2026-09-24T03:00:00.000Z',
      };
      final adapter = FakeBffAdapter({
        _community: (status: 200, body: envelope(channel)),
        'POST $_messages': (status: 200, body: envelope({'message': sent})),
      });
      final transport = FakeChannelTransport();
      final repo = RemoteCommunityRepository(
        fakeBffClient(adapter, userToken: () async => 'user-jwt'),
        transport: transport,
      );

      final seen = <List<ChatMessage>>[];
      final subscription = repo.watchChannel(_id).listen(seen.add);
      await pumpEventQueue();
      expect(transport.last.topic, 'district-chat:$_id');
      transport.last.accept();
      await pumpEventQueue();
      final readsBefore = adapter.requests.where((r) => r.method == 'GET');

      await repo.send(_id, '안녕');
      // The broadcast carries no `mine`; the sender's copy wins.
      transport.last.broadcast('message', {...sent}..remove('mine'));
      transport.last.broadcast('message', {
        'id': 'm10',
        'author': '솔숲 42',
        'body': '반갑습니다',
        'verifiedResident': true,
      });
      await pumpEventQueue();

      expect(
        adapter.requests.where((r) => r.method == 'GET'),
        hasLength(readsBefore.length),
      );
      final ids = [for (final m in seen.last) m.id];
      expect(ids.where((id) => id == 'm9'), hasLength(1));
      expect(ids.last, 'm10');
      expect(seen.last.firstWhere((m) => m.id == 'm9').mine, isTrue);

      transport.last.broadcast('delete', {'id': 'm10', 'deleted': true});
      await pumpEventQueue();
      expect(seen.last.map((m) => m.id), isNot(contains('m10')));

      await subscription.cancel();
      expect(transport.open, isEmpty, reason: 'leaving closes the socket');
    });

    test('a refused message is a write failure the screen can show', () async {
      final repo = RemoteCommunityRepository(
        fakeBffClient(
          FakeBffAdapter({
            'POST $_messages': (
              status: 403,
              body: errorWith('residency_required'),
            ),
          }),
          userToken: () async => 'user-jwt',
        ),
      );

      await expectLater(
        repo.send(_id, '안녕'),
        throwsA(isA<CommunityWriteException>()),
      );
    });
  });
}
