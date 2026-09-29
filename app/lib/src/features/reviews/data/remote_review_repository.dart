import 'dart:async';

import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/reviews/data/live_channel.dart';
import 'package:democracy/src/features/reviews/domain/channel_event.dart';
import 'package:democracy/src/features/reviews/domain/community_write_failure.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';

/// Runs a write; a refusal the author can act on comes back as a
/// [CommunityWriteException]. A refused session passes through untouched so
/// the caller can answer it with the sign-in-again sheet.
Future<T> _write<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on SessionExpiredException {
    rethrow;
  } on BffException catch (error) {
    throw CommunityWriteException.fromCode(
      error.code,
      reason: error.details['reason'],
    );
  }
}

String _district(String id) => '/districts/${Uri.encodeComponent(id)}';

/// Resident reviews from the BFF.
///
/// Reading is public; writing goes out with the signed-in person's token,
/// which [BffClient] attaches, and the server checks the residency for this
/// district itself -- the app's verified flag decides only whether to open
/// the compose page.
class RemoteReviewRepository implements ReviewRepository {
  const RemoteReviewRepository(this.client);

  final BffClient client;

  @override
  Future<ReviewBoard> loadBoard(String districtId) async {
    final response = await client.get(
      '${_district(districtId)}/reviews',
      cacheable: true,
    );
    return ReviewBoard.fromJson(response.data);
  }

  @override
  Future<ReviewBoard> submit(String districtId, ReviewDraft draft) =>
      _write(() async {
        final response = await client.post(
          '${_district(districtId)}/reviews',
          body: {
            'scores': draft.scores,
            'body': draft.body.trim(),
            'anonymous': draft.anonymous,
          },
        );
        return ReviewBoard.fromJson(response.data);
      });
}

/// The district channel and its threads from the BFF.
///
/// The channel is read over the BFF and then kept current by the district's
/// broadcast topic when a [transport] is given ([LiveChannel]). The socket
/// only adds to the read: without it, or while it is down, the channel is
/// read when it is opened and again after each message this device sends,
/// as it was before the socket existed.
///
/// A sent message is shown from the POST answer at once, marked as the
/// reader's own; the same message coming back over the socket has the same
/// id and is not shown twice.
///
/// Threads are opened on the server from the incumbent's bills; nothing here
/// creates one.
class RemoteCommunityRepository implements CommunityRepository {
  RemoteCommunityRepository(this.client, {this.transport, this.foreground});

  final BffClient client;

  /// Where broadcasts come from. Null reads only.
  final ChannelTransport? transport;

  /// A fresh foreground signal per open channel; the socket is let go while
  /// the app is in the background.
  final Stream<bool> Function()? foreground;

  /// The topic a district's channel is broadcast on (the server's
  /// channel_broadcast migration).
  static String topicFor(String districtId) => 'district-chat:$districtId';

  final _open = <String, Set<LiveChannel>>{};

  /// Ids of the messages this device sent, so a re-read by a signed-out
  /// reader (whose answer carries no `mine`) still shows them as its own.
  final _mine = <String>{};

  Future<Map<String, Object?>> _load(String districtId) async {
    final response = await client.get(
      '${_district(districtId)}/community',
      cacheable: true,
    );
    return response.data;
  }

  static List<ChatMessage> _messages(Map<String, Object?> data) {
    final raw = data['messages'];
    return List.unmodifiable(
      raw is List ? raw.map(ChatMessage.fromJson) : const <ChatMessage>[],
    );
  }

  @override
  Stream<List<ChatMessage>> watchChannel(String districtId) {
    late final StreamController<List<ChatMessage>> out;
    LiveChannel? live;
    out = StreamController<List<ChatMessage>>(
      onListen: () {
        final channel = LiveChannel(
          topic: topicFor(districtId),
          read: () async => _messages(await _load(districtId)),
          onChange: out.add,
          onError: out.addError,
          transport: transport,
          foreground: foreground?.call(),
          mine: _mine,
        );
        live = channel;
        _open.putIfAbsent(districtId, () => {}).add(channel);
        channel.start();
      },
      onCancel: () async {
        final channel = live;
        if (channel == null) {
          return;
        }
        _open[districtId]?.remove(channel);
        await channel.close();
      },
    );
    return out.stream;
  }

  @override
  Future<void> send(String districtId, String body) async {
    final response = await _write(
      () => client.post(
        '${_district(districtId)}/messages',
        // The channel has no anonymity switch, so it takes the default the
        // compose page does: the choice that cannot be taken back is never
        // made by omission.
        body: {'body': body.trim(), 'anonymous': true},
      ),
    );

    ChatMessage? sent;
    try {
      sent = ChatMessage.fromJson(response.data['message']).asMine();
      _mine.add(sent.id);
    } on FormatException {
      // Posted, but the answer did not say what; a read will show it.
    }

    for (final channel in [...?_open[districtId]]) {
      if (sent != null) {
        channel.add(MessagePosted(sent));
      }
      // Without a live socket, what others said meanwhile shows only on a
      // read. The message is posted either way; a failed read only delays
      // seeing the rest.
      if (sent == null || !channel.isLive) {
        await channel.refresh();
      }
    }
  }

  @override
  Future<List<DiscussionThread>> loadThreads(String districtId) async {
    final raw = (await _load(districtId))['threads'];
    return List.unmodifiable(
      raw is List
          ? raw.map(DiscussionThread.fromJson)
          : const <DiscussionThread>[],
    );
  }
}
