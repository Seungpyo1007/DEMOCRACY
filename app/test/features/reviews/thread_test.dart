import 'dart:convert';

import 'package:democracy/src/features/reviews/data/remote_thread_repository.dart';
import 'package:democracy/src/features/reviews/domain/community_write_failure.dart';
import 'package:democracy/src/features/reviews/domain/discussion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_bff.dart';
import '../../support/fake_channel_transport.dart';
import 'remote_review_repository_test.dart' show errorWith, fixture;

const _id = 'bill-PRC_X1';
const _path = '/threads/$_id';

ThreadReply _reply(String id, {bool mine = false}) => ThreadReply(
  id: id,
  author: '익명 주민',
  body: '답글 $id',
  verifiedResident: true,
  mine: mine,
  createdAt: DateTime.utc(2026, 9, 1, 10),
);

ThreadPage _page(List<ThreadReply> replies, {String? next}) => ThreadPage(
  thread: ThreadPage.fromJson(fixture('thread_fixture-thread-1')).thread,
  replies: replies,
  nextCursor: next,
);

void main() {
  group('parsing', () {
    test('the fixture is a thread page with its bill and source', () {
      final page = ThreadPage.fromJson(fixture('thread_fixture-thread-1'));
      expect(page.thread.title, '역세권 청년주택 공급 촉진법 개정안');
      expect(page.thread.districtId, 'fixture-seoul-mapo-b');
      expect(page.thread.bill?.stage, '위원회 심사');
      expect(page.thread.bill?.proposedLabel, '2026. 7. 21.');
      expect(page.thread.source.sourceUrl.host, 'likms.assembly.go.kr');
      expect(page.replies, hasLength(4));
      expect(page.replies[2].hidden, isTrue);
      expect(page.nextCursor, isNull);
    });

    test('a thread with no bill still opens', () {
      final page = ThreadPage.fromJson(fixture('thread_fixture-thread-2'));
      expect(page.thread.bill, isNull);
      expect(page.replies, hasLength(2));
    });

    test('a thread without a source is refused', () {
      final raw = fixture('thread_fixture-thread-3');
      (raw['thread']! as Map<String, Object?>).remove('source');
      expect(() => ThreadPage.fromJson(raw), throwsA(anything));
    });

    test('broadcasts: reply, hidden, delete; unknown ones are skipped', () {
      final posted = ThreadEvent.fromBroadcast('reply', {
        'id': 'r1',
        'author': '익명 주민',
        'body': '안녕',
        'authorTag': 'tag1',
        'createdAt': '2026-09-01T10:00:00.000Z',
      });
      expect(posted, isA<ReplyPosted>());
      expect((posted! as ReplyPosted).reply.authorTag, 'tag1');
      expect(
        ThreadEvent.fromBroadcast('hidden', {'id': 'r1', 'body': 'x'}),
        isA<ReplyChanged>(),
      );
      expect(
        ThreadEvent.fromBroadcast('delete', {'id': 'r1', 'deleted': true}),
        isA<ReplyDeleted>(),
      );
      expect(ThreadEvent.fromBroadcast('message', {'id': 'm'}), isNull);
      expect(ThreadEvent.fromBroadcast('reply', {'body': 'no id'}), isNull);
    });

    test('a reply makes a cursor from its time and id', () {
      expect(_reply('r1').cursor, '2026-09-01T10:00:00.000Z|r1');
    });
  });

  group('the open thread', () {
    test('a new reply at the end goes on the list and moves the count', () {
      final view = ThreadView.first(_page([_reply('a')])).add(_reply('b'));
      expect(view.replies.map((r) => r.id), ['a', 'b']);
      expect(view.count, ThreadView.first(_page([])).count + 1);
    });

    test('a reply that arrives before later pages waits after them', () {
      var view = ThreadView.first(_page([_reply('a')], next: 'c1'));
      view = view.add(_reply('z', mine: true));
      expect(view.replies.map((r) => r.id), ['a']);
      expect(view.tail.map((r) => r.id), ['z']);

      view = view.appendPage(_page([_reply('b')], next: 'c2'));
      expect(view.replies.map((r) => r.id), ['a', 'b']);
      expect(view.tail.map((r) => r.id), ['z']);

      // The last page carries the waiting reply too; it is kept once, as mine.
      view = view.appendPage(_page([_reply('c'), _reply('z')]));
      expect(view.replies.map((r) => r.id), ['a', 'b', 'c', 'z']);
      expect(view.replies.last.mine, isTrue);
      expect(view.tail, isEmpty);
      expect(view.atEnd, isTrue);
    });

    test('a broadcast of one\'s own reply does not show it twice', () {
      var view = ThreadView.first(_page([])).add(_reply('a', mine: true));
      view = view.apply(ReplyPosted(_reply('a')));
      expect(view.replies, hasLength(1));
      expect(view.replies.single.mine, isTrue);
    });

    test('hidden and deleted replies change in place', () {
      var view = ThreadView.first(
        _page([_reply('a', mine: true), _reply('b')]),
      );
      final count = view.count;
      view = view.apply(
        const ReplyChanged(
          ThreadReply(
            id: 'a',
            author: '익명 주민',
            body: '신고로 가려진 글입니다.',
            verifiedResident: true,
            hidden: true,
          ),
        ),
      );
      expect(view.replies.first.hidden, isTrue);
      expect(view.replies.first.mine, isTrue);
      view = view.apply(const ReplyDeleted('b'));
      expect(view.replies.map((r) => r.id), ['a']);
      expect(view.count, count > 0 ? count - 1 : 0);
      expect(view.apply(const ReplyDeleted('nope')), same(view));
    });
  });

  group('remote', () {
    test('reads a page, and the next one after its cursor', () async {
      final adapter = FakeBffAdapter({
        _path: (
          status: 200,
          body: envelope(fixture('thread_fixture-thread-1')),
        ),
      });
      final repo = RemoteThreadRepository(fakeBffClient(adapter));

      expect((await repo.load(_id)).replies, hasLength(4));
      await repo.load(_id, after: '2026-09-01T10:00:00.000Z|r1');
      expect(
        adapter.requests.last.queryParameters['after'],
        '2026-09-01T10:00:00.000Z|r1',
      );
    });

    test('posts anonymously and marks the answer as mine', () async {
      final adapter = FakeBffAdapter({
        'POST $_path/replies': (
          status: 200,
          body: envelope({
            'reply': {
              'id': 'r1',
              'author': '익명 주민',
              'body': '안녕',
              'verifiedResident': true,
              'mine': false,
              'createdAt': '2026-09-01T10:00:00.000Z',
            },
          }),
        ),
      });
      final reply = await RemoteThreadRepository(
        fakeBffClient(adapter),
      ).reply(_id, '  안녕 ');

      expect(reply.mine, isTrue);
      expect(json.decode(adapter.requests.single.data as String), {
        'body': '안녕',
        'anonymous': true,
      });
    });

    test('a refused reply says why, like a refused message', () async {
      Future<CommunityWriteException> refused(
        String code, [
        Map<String, Object?>? extra,
      ]) async {
        final repo = RemoteThreadRepository(
          fakeBffClient(
            FakeBffAdapter({
              'POST $_path/replies': (
                status: 403,
                body: errorWith(code, extra),
              ),
            }),
          ),
        );
        try {
          await repo.reply(_id, '안녕');
        } on CommunityWriteException catch (e) {
          return e;
        }
        throw StateError('not refused');
      }

      expect((await refused('residency_required')).residencyLost, isTrue);
      expect((await refused('rate_limited')).message, contains('1분'));
      expect(
        (await refused('content_rejected', {'reason': 'hate'})).warning,
        isNotNull,
      );
    });

    test('deleting what is already gone is not a failure', () async {
      final repo = RemoteThreadRepository(
        fakeBffClient(
          FakeBffAdapter({
            'DELETE /replies/r1': (status: 404, body: errorWith('not_found')),
            'DELETE /replies/r2': (status: 403, body: errorWith('forbidden')),
          }),
        ),
      );
      await repo.delete('r1');
      await expectLater(
        repo.delete('r2'),
        throwsA(isA<CommunityWriteException>()),
      );
    });

    test(
      'listens on thread:<id>, retries a failed join, says when it is back',
      () async {
        final transport = FakeChannelTransport();
        final timers = ManualTimers();
        final repo = RemoteThreadRepository(
          fakeBffClient(FakeBffAdapter({})),
          transport: transport,
          schedule: timers.call,
        );
        final events = <ThreadEvent>[];
        final sub = repo.watch(_id).listen(events.add);
        await Future<void>.delayed(Duration.zero);

        expect(transport.last.topic, 'thread:$_id');
        transport.last
          ..accept()
          ..broadcast('reply', {'id': 'r1', 'body': '안녕'});
        await Future<void>.delayed(Duration.zero);
        expect(events.single, isA<ReplyPosted>());

        transport.last.fail();
        expect(transport.last.closed, isTrue);
        expect(timers.delays.single, const Duration(seconds: 1));
        timers.fireLast();
        expect(transport.joins, hasLength(2));
        transport.last.accept();
        await Future<void>.delayed(Duration.zero);
        expect(events.last, isA<ThreadRejoined>());

        await sub.cancel();
        expect(transport.open, isEmpty);
      },
    );

    test('without a socket, there is nothing to listen to', () async {
      final repo = RemoteThreadRepository(fakeBffClient(FakeBffAdapter({})));
      expect(await repo.watch(_id).isEmpty, isTrue);
    });
  });
}
