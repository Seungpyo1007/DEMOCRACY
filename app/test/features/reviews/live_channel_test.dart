import 'dart:async';

import 'package:democracy/src/features/reviews/data/live_channel.dart';
import 'package:democracy/src/features/reviews/data/realtime_channel_transport.dart';
import 'package:democracy/src/features/reviews/domain/channel_event.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_channel_transport.dart';

ChatMessage _m(String id, {bool mine = false, String author = '익명 주민'}) =>
    ChatMessage(
      id: id,
      author: author,
      body: 'body $id',
      verifiedResident: true,
      mine: mine,
    );

/// What the server broadcasts for one message (the trigger's payload).
Map<String, Object?> _wire(String id, {String author = '익명 주민'}) => {
  'id': id,
  'author': author,
  'body': 'body $id',
  'verifiedResident': true,
  'createdAt': '2026-09-30T03:00:00.000Z',
};

List<String> _ids(List<ChatMessage> messages) => [
  for (final m in messages) m.id,
];

void main() {
  group('ChannelLog', () {
    test('appends a new message and drops a second copy', () {
      final log = ChannelLog.read([_m('a'), _m('b')])
          .apply(MessagePosted(_m('c')))
          .apply(MessagePosted(_m('c')))
          .apply(MessagePosted(_m('a')));

      expect(_ids(log.messages), ['a', 'b', 'c']);
    });

    test('the sender\'s copy marks it as theirs, whichever came first', () {
      // Broadcast first, then the POST answer.
      final socketFirst = ChannelLog.read(
        [_m('a')],
      ).apply(MessagePosted(_m('b'))).apply(MessagePosted(_m('b', mine: true)));
      // The POST answer first, then the broadcast, which cannot know.
      final postFirst = ChannelLog.read(
        [_m('a')],
      ).apply(MessagePosted(_m('b', mine: true))).apply(MessagePosted(_m('b')));

      for (final log in [socketFirst, postFirst]) {
        expect(_ids(log.messages), ['a', 'b']);
        expect(log.messages.last.mine, isTrue);
      }
    });

    test('a delete removes the message; an unknown one changes nothing', () {
      final log = ChannelLog.read([_m('a'), _m('b')]);

      expect(_ids(log.apply(const MessageDeleted('a')).messages), ['b']);
      expect(identical(log.apply(const MessageDeleted('zz')), log), isTrue);
    });

    test('keeps at most the newest ${ChannelLog.capacity}', () {
      var log = ChannelLog.empty;
      for (var i = 0; i < ChannelLog.capacity + 5; i++) {
        log = log.apply(MessagePosted(_m('$i')));
      }

      expect(log.messages, hasLength(ChannelLog.capacity));
      expect(log.messages.first.id, '5');
    });

    test('marks the ids this device sent', () {
      final log = ChannelLog.read([_m('a'), _m('b')]).markMine({'b'});

      expect([for (final m in log.messages) m.mine], [false, true]);
    });

    test('reads the two broadcasts the server sends, and skips the rest', () {
      final posted = ChannelEvent.fromBroadcast('message', _wire('a'));
      final deleted = ChannelEvent.fromBroadcast('delete', {
        'id': 'a',
        'deleted': true,
      });

      expect((posted! as MessagePosted).message.id, 'a');
      expect((posted as MessagePosted).message.mine, isFalse);
      expect((deleted! as MessageDeleted).id, 'a');
      expect(ChannelEvent.fromBroadcast('message', {'body': 'no id'}), isNull);
      expect(ChannelEvent.fromBroadcast('typing', _wire('a')), isNull);
    });
  });

  group('LiveChannel', () {
    late FakeChannelTransport transport;
    late ManualTimers timers;
    late List<List<ChatMessage>> server;
    late int reads;
    late List<List<ChatMessage>> shown;
    late List<Object> errors;
    late StreamController<bool> foreground;

    LiveChannel open({ChannelTransport? via, Set<String> mine = const {}}) {
      final channel = LiveChannel(
        topic: 'district-chat:nec-1',
        read: () async {
          reads += 1;
          return server.last;
        },
        onChange: shown.add,
        onError: (error, _) => errors.add(error),
        transport: via,
        foreground: foreground.stream,
        mine: mine,
        schedule: timers.call,
      )..start();
      return channel;
    }

    setUp(() {
      transport = FakeChannelTransport();
      timers = ManualTimers();
      server = [
        [_m('a'), _m('b')],
      ];
      reads = 0;
      shown = [];
      errors = [];
      foreground = StreamController<bool>.broadcast();
    });

    tearDown(() => foreground.close());

    test('reads, joins the district topic, and re-reads once joined', () async {
      final channel = open(via: transport);
      await pumpEventQueue();

      expect(channel.status, LiveChannelStatus.connecting);
      expect(transport.last.topic, 'district-chat:nec-1');
      expect(_ids(shown.single), ['a', 'b']);

      server.add([_m('a'), _m('b'), _m('c')]);
      transport.last.accept();
      await pumpEventQueue();

      expect(channel.status, LiveChannelStatus.live);
      expect(channel.isLive, isTrue);
      expect(reads, 2);
      expect(_ids(shown.last), ['a', 'b', 'c']);
    });

    test(
      'folds broadcasts in, without duplicates, and handles deletes',
      () async {
        final channel = open(via: transport);
        transport.last.accept();
        await pumpEventQueue();
        final before = shown.length;

        transport.last
          ..broadcast('message', _wire('c', author: '솔숲 42'))
          ..broadcast('message', _wire('c', author: '솔숲 42'))
          ..broadcast('delete', {'id': 'a', 'deleted': true})
          ..broadcast('unknown', {'id': 'x'});

        expect(_ids(channel.messages), ['b', 'c']);
        expect(channel.messages.last.author, '솔숲 42');
        // One change for the new message, one for the delete.
        expect(shown.length - before, 2);
      },
    );

    test(
      'an event during a re-read is kept on top of what it returns',
      () async {
        final slow = Completer<List<ChatMessage>>();
        var first = true;
        final channel = LiveChannel(
          topic: 't',
          read: () async {
            if (first) {
              first = false;
              return [_m('a')];
            }
            return slow.future;
          },
          onChange: shown.add,
          onError: (error, _) => errors.add(error),
          transport: transport,
          schedule: timers.call,
        )..start();
        await pumpEventQueue();

        transport.last.accept(); // starts the slow re-read
        transport.last.broadcast('message', _wire('late'));
        slow.complete([_m('a'), _m('b')]);
        await pumpEventQueue();

        expect(_ids(channel.messages), ['a', 'b', 'late']);
        await channel.close();
      },
    );

    test('a failed link is dropped and retried with growing backoff', () async {
      final channel = open(via: transport);
      await pumpEventQueue();

      transport.last.fail();
      expect(channel.status, LiveChannelStatus.retrying);
      expect(transport.joins.first.closed, isTrue);
      timers.fireLast();
      transport.last.fail();
      timers.fireLast();
      transport.last.fail();

      expect(timers.delays, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
      expect(transport.joins, hasLength(3));

      // Joining again resets the backoff and re-reads what was missed.
      timers.fireLast();
      server.add([_m('a'), _m('b'), _m('missed')]);
      transport.last.accept();
      await pumpEventQueue();
      expect(channel.status, LiveChannelStatus.live);
      expect(_ids(channel.messages), ['a', 'b', 'missed']);

      transport.last.fail();
      expect(timers.delays.last, const Duration(seconds: 1));
      await channel.close();
    });

    test('backoff stops growing at 30 seconds', () {
      expect(channelBackoff(1), const Duration(seconds: 1));
      expect(channelBackoff(5), const Duration(seconds: 16));
      expect(channelBackoff(6), const Duration(seconds: 30));
      expect(channelBackoff(40), const Duration(seconds: 30));
    });

    test('while the socket is down the channel still shows the read', () async {
      final channel = open(via: transport);
      await pumpEventQueue();
      transport.last.fail();

      expect(_ids(shown.single), ['a', 'b']);
      expect(errors, isEmpty);
      expect(channel.isLive, isFalse, reason: 'a sender must read again');
    });

    test('nothing a closed link reports is heard', () async {
      final channel = open(via: transport);
      await pumpEventQueue();
      final stale = transport.last..fail();
      timers.fireLast();

      stale
        ..broadcast('message', _wire('ghost'))
        ..accept();

      expect(channel.status, LiveChannelStatus.connecting);
      expect(_ids(channel.messages), ['a', 'b']);
      await channel.close();
    });

    test('lets go in the background and rejoins on return', () async {
      final channel = open(via: transport);
      transport.last.accept();
      await pumpEventQueue();

      foreground.add(false);
      await pumpEventQueue();
      expect(channel.status, LiveChannelStatus.paused);
      expect(transport.open, isEmpty);

      server.add([_m('a'), _m('b'), _m('while away')]);
      foreground.add(true);
      await pumpEventQueue();
      expect(transport.joins, hasLength(2));
      transport.last.accept();
      await pumpEventQueue();

      expect(channel.status, LiveChannelStatus.live);
      expect(_ids(channel.messages), ['a', 'b', 'while away']);
      await channel.close();
    });

    test('a retry pending in the background is not run', () async {
      final channel = open(via: transport);
      await pumpEventQueue();
      transport.last.fail();

      foreground.add(false);
      await pumpEventQueue();

      expect(timers.lastCancelled, isTrue);
      expect(channel.status, LiveChannelStatus.paused);
      await channel.close();
    });

    test('closing drops the link and stops everything', () async {
      final channel = open(via: transport);
      transport.last.accept();
      await pumpEventQueue();
      final before = shown.length;

      await channel.close();
      transport.last.broadcast('message', _wire('after'));
      foreground.add(true);
      await pumpEventQueue();

      expect(channel.status, LiveChannelStatus.closed);
      expect(transport.open, isEmpty);
      expect(transport.joins, hasLength(1));
      expect(shown, hasLength(before));
    });

    test('without a transport it reads, and reads again on return', () async {
      final channel = open();
      await pumpEventQueue();
      expect(channel.status, LiveChannelStatus.idle);

      server.add([_m('a'), _m('b'), _m('c')]);
      foreground.add(true);
      await pumpEventQueue();

      expect(reads, 2);
      expect(_ids(channel.messages), ['a', 'b', 'c']);
      await channel.close();
    });

    test('a failed first read is an error; a later one is not', () async {
      var fail = true;
      final channel = LiveChannel(
        topic: 't',
        read: () async {
          if (fail) {
            throw StateError('offline');
          }
          return [_m('a')];
        },
        onChange: shown.add,
        onError: (error, _) => errors.add(error),
        transport: transport,
        schedule: timers.call,
      )..start();
      await pumpEventQueue();
      expect(errors, hasLength(1));

      // The join's re-read recovers the channel.
      fail = false;
      transport.last.accept();
      await pumpEventQueue();
      expect(_ids(shown.single), ['a']);

      fail = true;
      await channel.refresh();
      expect(errors, hasLength(1));
      await channel.close();
    });

    test('messages this device sent are marked after a re-read', () async {
      final channel = open(via: transport, mine: {'b'});
      await pumpEventQueue();

      expect([for (final m in channel.messages) m.mine], [false, true]);
      await channel.close();
    });
  });

  group('RealtimeChannelTransport', () {
    test('lives beside the project at /realtime/v1', () {
      expect(
        RealtimeChannelTransport.realtimeEndpoint(
          Uri.parse('https://abc.supabase.co/'),
        ),
        'wss://abc.supabase.co/realtime/v1',
      );
      expect(
        RealtimeChannelTransport.realtimeEndpoint(
          Uri.parse('http://127.0.0.1:54321/'),
        ),
        'ws://127.0.0.1:54321/realtime/v1',
      );
    });

    test('a broadcast\'s message is its inner payload', () {
      expect(
        RealtimeChannelTransport.broadcastBody({
          'type': 'broadcast',
          'event': 'message',
          'payload': _wire('a'),
        }),
        _wire('a'),
      );
    });
  });
}
