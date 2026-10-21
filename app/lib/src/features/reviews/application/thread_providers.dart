import 'dart:async';

import 'package:democracy/src/features/reviews/data/remote_thread_repository.dart';
import 'package:democracy/src/features/reviews/domain/discussion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final threadRepositoryProvider = Provider<ThreadRepository>(
  (ref) => FakeThreadRepository(),
);

/// One open thread, kept current while its page is shown.
///
/// Disposed when the page closes, which cancels the broadcast stream and so
/// lets go of the topic.
final threadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadView, String>(ThreadController.new);

class ThreadController extends AsyncNotifier<ThreadView> {
  ThreadController(this.threadId);

  final String threadId;

  ThreadRepository get _repo => ref.read(threadRepositoryProvider);

  @override
  Future<ThreadView> build() async {
    final repo = ref.watch(threadRepositoryProvider);
    final events = repo.watch(threadId).listen(_onEvent);
    ref.onDispose(events.cancel);
    return ThreadView.first(await repo.load(threadId));
  }

  void _onEvent(ThreadEvent event) {
    final view = state.value;
    if (view == null) {
      return;
    }
    if (event is ThreadRejoined) {
      unawaited(_catchUp());
      return;
    }
    state = AsyncValue.data(view.apply(event));
  }

  /// After a drop: reads what came after the last reply shown. Nothing to do
  /// while later pages are unread; reaching them shows the rest.
  Future<void> _catchUp() async {
    final view = state.value;
    if (view == null || !view.atEnd || view.loadingMore) {
      return;
    }
    final last = view.replies.isEmpty ? null : view.replies.last;
    try {
      final page = await _repo.load(threadId, after: last?.cursor);
      final now = state.value;
      if (now == null) {
        return;
      }
      var next = now;
      for (final reply in page.replies) {
        next = next.add(reply);
      }
      state = AsyncValue.data(next.continuingAt(page.nextCursor));
    } on Object {
      // The list stays as it was; the next join tries again.
    }
  }

  Future<void> loadMore() async {
    final view = state.value;
    final cursor = view?.nextCursor;
    if (view == null || cursor == null || view.loadingMore) {
      return;
    }
    state = AsyncValue.data(view.loading());
    try {
      final page = await _repo.load(threadId, after: cursor);
      state = AsyncValue.data(state.requireValue.appendPage(page));
    } on Object {
      state = AsyncValue.data(state.requireValue.settled());
      rethrow;
    }
  }

  /// Posts a reply and shows it. Failures go to the caller, which says why.
  Future<void> post(String body) async {
    final reply = await _repo.reply(threadId, body);
    final view = state.value;
    if (view != null) {
      state = AsyncValue.data(view.add(reply));
    }
  }

  Future<void> delete(String replyId) async {
    await _repo.delete(replyId);
    final view = state.value;
    if (view != null) {
      state = AsyncValue.data(view.remove(replyId));
    }
  }
}
