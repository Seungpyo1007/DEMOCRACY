import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';

/// Reports and blocks through the BFF, with the signed-in person's token.
class RemoteModerationRepository implements ModerationRepository {
  const RemoteModerationRepository(this.client);

  final BffClient client;

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SessionExpiredException {
      rethrow;
    } on BffException catch (error) {
      throw ModerationException.fromCode(error.code);
    }
  }

  @override
  Future<ReportOutcome> report(
    PostKind kind,
    String id,
    ReportReason reason, {
    String? note,
  }) => _call(() async {
    final response = await client.post(
      '/reports',
      body: {
        'targetType': kind.wire,
        'targetId': id,
        'reason': reason.wire,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return response.data['hidden'] == true
        ? ReportOutcome.hidden
        : ReportOutcome.filed;
  });

  @override
  Future<BlockedAuthor> block(PostKind kind, String id) => _call(() async {
    final response = await client.post(
      '/blocks',
      body: {'targetType': kind.wire, 'targetId': id},
    );
    return BlockedAuthor.fromJson(response.data['block']);
  });

  @override
  Future<void> unblock(String blockId) =>
      _call(() => client.delete('/blocks/${Uri.encodeComponent(blockId)}'));

  @override
  Future<List<BlockedAuthor>> loadBlocks() => _call(() async {
    final response = await client.get('/blocks');
    final raw = response.data['blocks'];
    return List.unmodifiable(
      raw is List ? raw.map(BlockedAuthor.fromJson) : const <BlockedAuthor>[],
    );
  });
}

/// For builds without a BFF and for tests: everything is kept in memory.
class FakeModerationRepository implements ModerationRepository {
  FakeModerationRepository({DateTime? at})
    : _at = at ?? DateTime.utc(2026, 7, 30, 9);

  /// When every block says it was made; a fake has no clock of its own.
  final DateTime _at;

  final reports = <(PostKind, String, ReportReason)>[];
  final _blocks = <BlockedAuthor>[];

  @override
  Future<ReportOutcome> report(
    PostKind kind,
    String id,
    ReportReason reason, {
    String? note,
  }) async {
    if (reports.any((r) => r.$1 == kind && r.$2 == id)) {
      throw ModerationException.fromCode('conflict');
    }
    reports.add((kind, id, reason));
    return reason == ReportReason.privacy
        ? ReportOutcome.hidden
        : ReportOutcome.filed;
  }

  @override
  Future<BlockedAuthor> block(PostKind kind, String id) async {
    final block = BlockedAuthor(
      id: 'block-${_blocks.length + 1}',
      label: '익명 주민',
      createdAt: _at,
      authorTag: 'tag-$id',
    );
    _blocks.insert(0, block);
    return block;
  }

  @override
  Future<void> unblock(String blockId) async {
    _blocks.removeWhere((b) => b.id == blockId);
  }

  @override
  Future<List<BlockedAuthor>> loadBlocks() async => List.unmodifiable(_blocks);
}
