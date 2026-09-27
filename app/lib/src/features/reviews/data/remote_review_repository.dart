import 'dart:async';

import 'package:democracy/src/core/network/bff_client.dart';
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
/// There is no socket yet: the channel is read once when it is opened and
/// again after each message this device sends, so what was just written
/// shows among the others. Threads are opened on the server from the
/// incumbent's bills; nothing here creates one.
class RemoteCommunityRepository implements CommunityRepository {
  RemoteCommunityRepository(this.client);

  final BffClient client;

  final _updates =
      StreamController<
        ({String districtId, List<ChatMessage> messages})
      >.broadcast();

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
  Stream<List<ChatMessage>> watchChannel(String districtId) async* {
    yield _messages(await _load(districtId));
    yield* _updates.stream
        .where((update) => update.districtId == districtId)
        .map((update) => update.messages);
  }

  @override
  Future<void> send(String districtId, String body) async {
    await _write(
      () => client.post(
        '${_district(districtId)}/messages',
        // The channel has no anonymity switch, so it takes the default the
        // compose page does: the choice that cannot be taken back is never
        // made by omission.
        body: {'body': body.trim(), 'anonymous': true},
      ),
    );

    // The message is posted; a failed refresh only delays seeing it.
    try {
      final messages = _messages(await _load(districtId));
      _updates.add((districtId: districtId, messages: messages));
    } on BffException {
      // Shown on the next read.
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
