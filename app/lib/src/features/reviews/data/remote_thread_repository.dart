import 'dart:async';

import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/features/reviews/data/live_channel.dart';
import 'package:democracy/src/features/reviews/domain/community_write_failure.dart';
import 'package:democracy/src/features/reviews/domain/discussion.dart';

String _thread(String id) => '/threads/${Uri.encodeComponent(id)}';

/// Threads and their replies from the BFF.
///
/// Reading is public. Writing goes out with the signed-in person's token and
/// the server checks residency for the thread's district, the same rules as
/// the channel.
class RemoteThreadRepository implements ThreadRepository {
  RemoteThreadRepository(
    this.client, {
    this.transport,
    this.foreground,
    Timer Function(Duration, void Function())? schedule,
  }) : _schedule = schedule ?? Timer.new;

  final BffClient client;
  final ChannelTransport? transport;
  final Stream<bool> Function()? foreground;
  final Timer Function(Duration, void Function()) _schedule;

  /// The topic a thread's replies are broadcast on (the server's
  /// thread_replies migration).
  static String topicFor(String threadId) => 'thread:$threadId';

  @override
  Future<ThreadPage> load(String threadId, {String? after}) async {
    final response = await client.get(
      _thread(threadId),
      query: after == null ? null : {'after': after},
      // Only the first page is worth keeping for offline reading.
      cacheable: after == null,
    );
    return ThreadPage.fromJson(response.data);
  }

  @override
  Future<ThreadReply> reply(String threadId, String body) async {
    try {
      final response = await client.post(
        '${_thread(threadId)}/replies',
        // Anonymous, as in the channel: the choice that cannot be taken back
        // is never made by omission.
        body: {'body': body.trim(), 'anonymous': true},
      );
      return ThreadReply.fromJson(response.data['reply']).asMine();
    } on SessionExpiredException {
      rethrow;
    } on BffException catch (error) {
      throw CommunityWriteException.fromCode(
        error.code,
        reason: error.details['reason'],
      );
    }
  }

  @override
  Future<void> delete(String replyId) async {
    try {
      await client.delete('/replies/${Uri.encodeComponent(replyId)}');
    } on NotAvailableException {
      // Already gone is what was asked for.
    } on SessionExpiredException {
      rethrow;
    } on BffException {
      throw CommunityWriteException.generic;
    }
  }

  @override
  Stream<ThreadEvent> watch(String threadId) {
    final transport = this.transport;
    if (transport == null) {
      return const Stream.empty();
    }
    late final StreamController<ThreadEvent> out;
    _ThreadSocket? socket;
    out = StreamController<ThreadEvent>(
      onListen: () {
        socket = _ThreadSocket(
          topic: topicFor(threadId),
          transport: transport,
          foreground: foreground?.call(),
          schedule: _schedule,
          emit: out.add,
        )..start();
      },
      onCancel: () => socket?.close(),
    );
    return out.stream;
  }
}

/// Holds one thread's topic while it is listened to: joins, retries with
/// [channelBackoff], lets go in the background, and says when it joined
/// again so the reader can catch up.
class _ThreadSocket {
  _ThreadSocket({
    required this.topic,
    required this.transport,
    required this.foreground,
    required this.schedule,
    required this.emit,
  });

  final String topic;
  final ChannelTransport transport;
  final Stream<bool>? foreground;
  final Timer Function(Duration, void Function()) schedule;
  final void Function(ThreadEvent event) emit;

  ChannelLink? _link;
  int _generation = 0;
  int _attempt = 0;
  bool _closed = false;
  bool _joinedOnce = false;
  bool _paused = false;
  Timer? _retry;
  StreamSubscription<bool>? _foreground;

  void start() {
    _foreground = foreground?.listen((visible) {
      if (_closed) {
        return;
      }
      if (!visible) {
        _paused = true;
        _retry?.cancel();
        unawaited(_drop());
      } else if (_paused) {
        _paused = false;
        _attempt = 0;
        _connect();
      }
    });
    _connect();
  }

  void _connect() {
    if (_closed) {
      return;
    }
    final generation = ++_generation;
    _link = transport.join(
      topic,
      onEvent: (event, payload) {
        if (generation != _generation) {
          return;
        }
        final parsed = ThreadEvent.fromBroadcast(event, payload);
        if (parsed != null) {
          emit(parsed);
        }
      },
      onState: (state) {
        if (generation != _generation) {
          return;
        }
        switch (state) {
          case ChannelLinkState.joined:
            _attempt = 0;
            // The first join follows the first read; later ones follow a gap.
            if (_joinedOnce) {
              emit(const ThreadRejoined());
            }
            _joinedOnce = true;
          case ChannelLinkState.failed:
            unawaited(_drop());
            _attempt += 1;
            _retry = schedule(channelBackoff(_attempt), _connect);
        }
      },
    );
  }

  Future<void> _drop() async {
    _generation += 1;
    final link = _link;
    _link = null;
    await link?.close();
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _foreground?.cancel();
    await _drop();
  }
}

/// The bundled threads, plus replies written in this session.
class FakeThreadRepository implements ThreadRepository {
  FakeThreadRepository({this.loader = const FixtureLoader(), DateTime? at})
    : _at = at ?? DateTime.utc(2026, 7, 30, 9);

  final FixtureLoader loader;

  /// When every reply says it was written; a fake has no clock of its own.
  final DateTime _at;
  final _posted = <String, List<ThreadReply>>{};

  @override
  Future<ThreadPage> load(String threadId, {String? after}) async {
    final page = ThreadPage.fromJson(await loader.load('thread_$threadId'));
    final mine = _posted[threadId] ?? const [];
    return ThreadPage(
      thread: page.thread,
      replies: List.unmodifiable([...page.replies, ...mine]),
    );
  }

  @override
  Future<ThreadReply> reply(String threadId, String body) async {
    final list = _posted.putIfAbsent(threadId, () => []);
    final reply = ThreadReply(
      id: 'local-$threadId-${list.length + 1}',
      author: '익명 주민',
      body: body.trim(),
      verifiedResident: true,
      mine: true,
      createdAt: _at,
    );
    list.add(reply);
    return reply;
  }

  @override
  Future<void> delete(String replyId) async {
    for (final list in _posted.values) {
      list.removeWhere((r) => r.id == replyId);
    }
  }

  @override
  Stream<ThreadEvent> watch(String threadId) => const Stream.empty();
}
