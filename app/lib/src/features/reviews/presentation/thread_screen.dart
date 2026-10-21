import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/reviews/application/moderation_providers.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/application/thread_providers.dart';
import 'package:democracy/src/features/reviews/domain/discussion.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_parts.dart';
import 'package:democracy/src/features/reviews/presentation/moderation_actions.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One discussion thread: the bill that opened it, then the replies, oldest
/// first, and the field to add one.
///
/// Writing follows the channel's rules: a resident of the thread's district,
/// through the same gate, anonymous, refused wording held back before it is
/// sent.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({required this.threadId, super.key});

  final String threadId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _scroll = ScrollController();
  final _reply = TextEditingController();

  String? _notice;
  bool _acknowledged = false;
  bool _sending = false;

  @override
  void dispose() {
    _scroll.dispose();
    _reply.dispose();
    super.dispose();
  }

  ThreadController get _controller =>
      ref.read(threadProvider(widget.threadId).notifier);

  /// The reader may write here: verified, and in the thread's own district.
  bool _mayWrite(ThreadDetail? thread, {bool watch = false}) {
    final address = watch
        ? ref.watch(addressControllerProvider)
        : ref.read(addressControllerProvider);
    return address.isVerified &&
        thread != null &&
        address.district?.id == thread.districtId;
  }

  void _say(String? notice) {
    setState(() => _notice = notice);
    if (notice != null) {
      _revealEnd();
    }
  }

  void _revealEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      final end = _scroll.position.maxScrollExtent;
      if (AppMotion.reduced(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: AppMotion.base,
          curve: AppMotion.settle,
        );
      }
    });
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }
    final thread = ref.read(threadProvider(widget.threadId)).value?.thread;
    if (!_mayWrite(thread)) {
      _say('이 지역구 주민 인증을 마친 주민만 답글을 쓸 수 있습니다.');
      return;
    }

    // Same as the channel: a claim can be sent past on a second press, a
    // hate term cannot.
    final warning = ContentGuard.inspect(body);
    if (warning != null && (warning.blocks || !_acknowledged)) {
      _acknowledged = true;
      _say(warning.prompt('올리려면'));
      return;
    }

    setState(() => _sending = true);
    try {
      await _controller.post(body);
    } on Object catch (error) {
      await settleWriteFailure(
        error,
        onSessionExpired: () =>
            ref.read(authControllerProvider.notifier).sessionExpired(),
        onResidencyLost: () =>
            ref.read(addressControllerProvider.notifier).dropResidency(),
      );
      if (mounted) {
        setState(() => _sending = false);
        _say(writeFailureMessage(error));
      }
      return;
    }
    _reply.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _notice = null;
      _acknowledged = false;
    });
    _revealEnd();
  }

  Future<void> _loadMore() async {
    try {
      await _controller.loadMore();
    } on Object {
      if (mounted) {
        await PlatformAdaptiveNotice.show(
          context,
          message: '답글을 더 불러오지 못했습니다.',
        );
      }
    }
  }

  Future<void> _delete(String replyId) async {
    var confirmed = false;
    await PlatformAdaptiveDialog.show(
      context: context,
      title: '답글을 삭제할까요?',
      message: '삭제한 답글은 되돌릴 수 없습니다.',
      confirmLabel: '삭제',
      onConfirmed: () => confirmed = true,
      secondaryLabel: '취소',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await _controller.delete(replyId);
    } on Object catch (error) {
      await settleWriteFailure(
        error,
        onSessionExpired: () =>
            ref.read(authControllerProvider.notifier).sessionExpired(),
        onResidencyLost: () {},
      );
      if (mounted) {
        await PlatformAdaptiveNotice.show(
          context,
          message: '삭제하지 못했습니다. 잠시 뒤 다시 시도하세요.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(threadProvider(widget.threadId));
    final view = value.value;
    final enabled = _mayWrite(view?.thread, watch: true);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: EditorialScrollView(
              controller: _scroll,
              title: '정책 토론',
              kicker: view?.thread.origin,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                }
              },
              // The field floats over the end of the replies.
              bottomPadding: 56 + AppSpacing.x4 * 2,
              slivers: [
                SliverPadding(
                  padding: kPagePadding,
                  sliver: SliverToBoxAdapter(
                    child: AsyncSection<ThreadView>(
                      value: value,
                      onRetry: () =>
                          ref.invalidate(threadProvider(widget.threadId)),
                      builder: (context, data) => _Thread(
                        view: data,
                        notice: _notice,
                        onMore: _loadMore,
                        onDelete: _delete,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (view != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CommunityComposer(
                controller: _reply,
                enabled: enabled,
                onSend: _send,
                hint: '답글 쓰기',
                disabledHint: '이 지역구 주소 인증 주민만 쓸 수 있습니다',
              ),
            ),
        ],
      ),
    );
  }
}

class _Thread extends ConsumerWidget {
  const _Thread({
    required this.view,
    required this.notice,
    required this.onMore,
    required this.onDelete,
  });

  final ThreadView view;
  final String? notice;
  final VoidCallback onMore;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The server leaves blocked authors out of every page; what arrives over
    // the socket afterwards is matched on today's author tag.
    final blocked = ref.watch(blockedTagsProvider);
    bool shown(ThreadReply r) =>
        r.authorTag == null || !blocked.contains(r.authorTag);
    final replies = view.replies.where(shown).toList();
    final tail = view.tail.where(shown).toList();
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    Widget entry(ThreadReply r, int index) => RevealIn(
      key: ValueKey(r.id),
      index: index,
      child: _ReplyEntry(reply: r, onDelete: () => onDelete(r.id)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.x3 + 2),
        RevealIn(child: _BillCard(thread: view.thread)),
        const SizedBox(height: AppSpacing.x6),
        RevealIn(
          index: 1,
          child: SectionHeader(
            number: '01',
            label: '답글',
            trailing: Text(
              '${view.count}개',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        const RevealIn(
          index: 2,
          child: DisclaimerBox(
            text:
                '이 지역구 주소 인증 주민만 작성 가능 · 오래된 순 · '
                '답글에 답글은 달 수 없음 · 글마다 ⋯에서 신고·숨기기',
          ),
        ),
        if (replies.isEmpty && tail.isEmpty && view.atEnd)
          const RevealIn(
            index: 3,
            child: CommunityEmptyNote(
              title: '아직 답글이 없습니다.',
              detail: '이 지역구 주소 인증 주민이 쓴 답글이 여기에 오래된 순으로 쌓입니다.',
            ),
          ),
        for (var i = 0; i < replies.length; i++) entry(replies[i], i + 3),
        if (!view.atEnd)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x3),
            child: view.loadingMore
                ? const InkLoadingRows(rows: 2)
                : AppSecondaryButton(label: '답글 더 보기', onPressed: onMore),
          ),
        for (final r in tail) entry(r, 0),
        AnimatedSize(
          duration: duration,
          curve: AppMotion.settle,
          alignment: Alignment.topCenter,
          child: notice == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.x4),
                  child: Semantics(
                    liveRegion: true,
                    child: DisclaimerBox(text: notice!),
                  ),
                ),
        ),
      ],
    );
  }
}

/// The bill the thread was opened from, between hairlines, with its source.
class _BillCard extends StatelessWidget {
  const _BillCard({required this.thread});

  final ThreadDetail thread;

  @override
  Widget build(BuildContext context) {
    final bill = thread.bill;
    final facts = <(String, String?)>[
      ('대표발의', bill?.proposer),
      ('소관 위원회', bill?.committee),
      ('단계', bill?.stage),
      ('발의일', bill?.proposedLabel),
    ].where((f) => f.$2 != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          thread.title,
          style: AppTextStyles.reading.copyWith(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        const Divider(height: 1, color: AppColors.divider),
        for (final (label, value) in facts)
          RuledRow(
            minHeight: 44,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    label,
                    style: AppTextStyles.disclaimer.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value!,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.x2),
        SourceBadge(source: thread.source),
      ],
    );
  }
}

/// One reply: who, when, and what, between hairlines.
class _ReplyEntry extends StatelessWidget {
  const _ReplyEntry({required this.reply, required this.onDelete});

  final ThreadReply reply;
  final VoidCallback onDelete;

  static const _ownItems = [
    AppMenuItem(label: '삭제하기', icon: AppIcon(Icons.delete_outline, 'trash')),
  ];

  @override
  Widget build(BuildContext context) {
    final at = reply.createdAt;
    final header = Wrap(
      spacing: AppSpacing.x2,
      runSpacing: AppSpacing.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          reply.mine ? '${reply.author} (나)' : reply.author,
          style: AppTextStyles.ctaSmall.copyWith(
            color: AppColors.ink,
            fontSize: 13,
          ),
        ),
        if (reply.verifiedResident) const VerifiedBadge(label: '인증'),
        if (at != null)
          Text(
            KstInstant.fromDateTime(at).stampLabel,
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
            ),
          ),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: header),
                if (reply.mine)
                  AppMenuButton(
                    key: ValueKey('reply-menu-${reply.id}'),
                    icon: const AppIcon(Icons.more_horiz, 'ellipsis'),
                    semanticLabel: '내 답글 메뉴',
                    items: _ownItems,
                    onSelected: (_) => onDelete(),
                  )
                else if (!reply.hidden)
                  PostMenu(kind: PostKind.reply, postId: reply.id),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            if (reply.hidden)
              HiddenPostBody(text: reply.body)
            else
              Text(
                reply.body,
                style: AppTextStyles.reading.copyWith(
                  color: AppColors.ink,
                  height: 1.6,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
