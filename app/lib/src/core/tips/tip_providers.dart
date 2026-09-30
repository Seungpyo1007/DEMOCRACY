import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tipStoreProvider = Provider<TipStore>((ref) => const DisabledTipStore());

/// The ids of the tips already dismissed.
final tipsControllerProvider =
    AsyncNotifierProvider<TipsController, Set<String>>(TipsController.new);

class TipsController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(tipStoreProvider).load();

  Future<void> dismiss(String id) async {
    state = AsyncData({...state.value ?? const {}, id});
    await ref.read(tipStoreProvider).markSeen(id);
  }

  /// 도움말 다시 보기: every tip shows again the next time its screen does.
  Future<void> replay() async {
    await ref.read(tipStoreProvider).reset();
    ref.invalidateSelf();
  }
}
