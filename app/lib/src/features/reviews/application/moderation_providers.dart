import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/features/reviews/data/remote_moderation_repository.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final moderationRepositoryProvider = Provider<ModerationRepository>(
  (ref) => FakeModerationRepository(),
);

/// The reader's blocks; empty when nobody is signed in.
final blocksProvider = FutureProvider<List<BlockedAuthor>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthSignedIn) {
    return const [];
  }
  return ref.watch(moderationRepositoryProvider).loadBlocks();
});

/// Today's tags of the blocked authors, for the live channel.
///
/// The server leaves blocked authors out of every list it sends; this only
/// covers what arrives over the socket after the list was read.
final blockedTagsProvider = Provider<Set<String>>((ref) {
  final blocks = ref.watch(blocksProvider).value ?? const [];
  return {
    for (final b in blocks)
      if (b.authorTag != null) b.authorTag!,
  };
});
