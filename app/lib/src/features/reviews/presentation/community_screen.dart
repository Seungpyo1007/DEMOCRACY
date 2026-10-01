import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_kicker.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:democracy/src/features/shell/application/tab_accessory.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Ratings, the channel and the threads, in one district hub.
///
/// Three tabs rather than three destinations because they are three ways of
/// saying the same thing about the same seat, and splitting them across the
/// bottom bar would make the district look like three communities.
///
/// The page is one scroll view under the platform's own header, so the tabs
/// swap only the content below them. What each tab lets the reader *do* --
/// write a review, send a message -- floats over the page at the bottom,
/// which is why the channel's field is owned here rather than by the tab
/// that shows it. The anonymous choice is not made here: it lives on the
/// compose page, beside the words it will be attached to.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  static const tabs = <String>['주민 평가', '지역 채팅', '정책 토론'];

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _scroll = ScrollController();
  final _message = TextEditingController();

  int _tab = 0;

  /// What held the last message back: a content warning, or why the server
  /// refused it. Shown at the foot of the channel, where it would have landed.
  String? _notice;
  bool _acknowledged = false;
  bool _sending = false;

  /// Someone else's message arrived while the reader was scrolled up. The
  /// page is not moved under them; a small 「새 메시지」 says so instead.
  bool _unseen = false;

  /// How close to the end counts as reading the newest messages.
  static const _followSlack = 96.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _message.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _tab) {
      return;
    }
    PlatformAdaptiveHaptics.selection();
    setState(() {
      _tab = index;
      _unseen = false;
    });
  }

  bool get _atEnd {
    if (!_scroll.hasClients) {
      return true;
    }
    final position = _scroll.position;
    return position.maxScrollExtent - position.pixels <= _followSlack;
  }

  void _onScroll() {
    if (_unseen && _atEnd) {
      setState(() => _unseen = false);
    }
  }

  /// A message landed in the open channel. A reader at the end is taken to
  /// it; one who scrolled up to read is left where they are.
  void _onChannel(
    AsyncValue<List<ChatMessage>>? previous,
    AsyncValue<List<ChatMessage>> next,
  ) {
    final before = previous?.value;
    final after = next.value;
    // The first read is not news; it is the channel.
    if (before == null || after == null || after.isEmpty) {
      return;
    }
    final newest = after.last;
    if (before.any((m) => m.id == newest.id)) {
      return;
    }
    // One's own message is brought into view by _send.
    if (newest.mine) {
      return;
    }
    if (_atEnd) {
      _revealLatest();
    } else if (!_unseen) {
      setState(() => _unseen = true);
    }
  }

  void _showUnseen() {
    setState(() => _unseen = false);
    _revealLatest();
  }

  /// The channel is read from the bottom, so what was just sent -- or the
  /// warning holding it back -- is brought into view beside the field.
  void _revealLatest() {
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
    final body = _message.text.trim();
    if (body.isEmpty) {
      return;
    }

    // Intercepted before it is sent, not moderated after. A message the author
    // can still take back is a different thing from one already delivered.
    // A claim can be sent past on a second press; a hate term cannot, as the
    // server refuses it too.
    final warning = ContentGuard.inspect(body);
    if (warning != null && (warning.blocks || !_acknowledged)) {
      setState(() {
        _notice = warning.prompt('보내려면');
        _acknowledged = true;
      });
      _revealLatest();
      return;
    }

    final district = ref.read(addressControllerProvider).district;
    if (district == null || _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(communityRepositoryProvider).send(district.id, body);
    } on Object catch (error) {
      await settleWriteFailure(
        error,
        onSessionExpired: () =>
            ref.read(authControllerProvider.notifier).sessionExpired(),
        onResidencyLost: () =>
            ref.read(addressControllerProvider.notifier).dropResidency(),
      );
      if (mounted) {
        // The message stays in the field, to send again or change.
        setState(() {
          _sending = false;
          _notice = writeFailureMessage(error);
        });
        _revealLatest();
      }
      return;
    }
    _message.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _notice = null;
      _acknowledged = false;
    });
    _revealLatest();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final verified = ref.watch(addressControllerProvider).isVerified;

    // Only while the channel is the open tab: the socket behind it is held
    // for as long as anything listens.
    if (_tab == 1) {
      ref.listen(channelProvider, _onChannel);
    }

    // The channel's field is a bar across the foot; the review tab's write
    // action is a compact floating button, placed as the tracker's is.
    final composer = _tab == 1
        ? _Composer(controller: _message, enabled: verified, onSend: _send)
        : null;

    return TabAccessoryScope(
      slot: TabSlot.community,
      // Only the reviews pane has a single primary action to lend.
      accessory: _tab == 0 && tabBarTakesAction(context)
          ? _ComposeAction.accessory(context, ref)
          : null,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: EditorialScrollView(
                controller: _scroll,
                title: '커뮤니티',
                kicker: communityKicker(ref),
                floatingAction: _tab == 0 && !tabBarTakesAction(context)
                    ? const _ComposeAction()
                    : null,
                // The composer floats over the end of the channel.
                bottomPadding: composer == null
                    ? AppSpacing.x8
                    : 56 + AppSpacing.x4 * 2,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.x2,
                      AppSpacing.screen,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: InlineTabs(
                        labels: CommunityScreen.tabs,
                        selectedIndex: _tab,
                        onSelected: _select,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: reduced ? Duration.zero : AppMotion.base,
                      reverseDuration: AppMotion.leave,
                      switchInCurve: AppMotion.settle,
                      switchOutCurve: AppMotion.settle,
                      // The outgoing tab fades without moving; only the
                      // incoming one rises, so the two never look like they
                      // are sliding past each other.
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.015),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: switch (_tab) {
                          0 => const _ReviewTab(),
                          1 => _ChannelTab(notice: _notice),
                          _ => const _ThreadTab(),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (composer != null && _unseen)
              Positioned(
                left: 0,
                right: 0,
                bottom:
                    56 +
                    AppSpacing.x4 * 2 +
                    MediaQuery.paddingOf(context).bottom,
                child: Center(child: _NewMessages(onPressed: _showUnseen)),
              ),
            if (composer != null)
              Positioned(left: 0, right: 0, bottom: 0, child: composer),
          ],
        ),
      ),
    );
  }
}

/// The ratings: the summary, the rule about who may write, then the reviews.
class _ReviewTab extends ConsumerWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(reviewBoardProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.screen,
        AppSpacing.screen,
        0,
      ),
      child: AsyncSection<ReviewBoard>(
        value: board,
        onRetry: () => ref.invalidate(reviewBoardProvider),
        builder: (context, data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A seat no one has rated yet has no average: saying 0.0 would
            // read as a verdict nobody gave.
            RevealIn(
              child: data.summary.isEmpty
                  ? const _EmptyNote(
                      title: '아직 올라온 평가가 없습니다.',
                      detail:
                          '이 지역구 주소 인증을 마친 주민이 평가를 올리면 '
                          '평균과 항목별 점수가 여기에 모입니다.',
                    )
                  : _Summary(summary: data.summary),
            ),
            const SizedBox(height: 18),
            const RevealIn(
              index: 1,
              child: DisclaimerBox(
                text:
                    // What the app actually does: residency, a fixed list
                    // of hate terms refused, and a warning (not a block)
                    // on claims that may be false.
                    '주소 인증 주민만 작성 가능 · 혐오 표현은 올라가지 않음 · '
                    '사실과 다를 수 있는 주장엔 경고',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            for (var i = 0; i < data.reviews.length; i++)
              RevealIn(
                key: ValueKey(data.reviews[i].id),
                index: i + 2,
                child: _ReviewEntry(review: data.reviews[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a tab says when there is nothing in it yet: a real district starts
/// empty, and that should read as a beginning rather than a failure.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.reading.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            detail,
            style: AppTextStyles.cardBody.copyWith(
              color: AppColors.neutral600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The average, large, beside the four axes it is the mean of.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Figure(
                  value: summary.average,
                  fractionDigits: 1,
                  style: AppTextStyles.ratingDisplay.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                summary.respondentsDisplay,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < summary.axes.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.x2 + 2),
                LabeledBar(
                  label: summary.axes[i].label,
                  fraction: summary.axes[i].score / 5,
                  valueText: summary.axes[i].display,
                  labelWidth: 64,
                  valueWidth: 30,
                  trackHeight: 8,
                  delay: AppMotion.staggerFor(i + 1),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One review, set as a quoted passage between hairlines.
class _ReviewEntry extends StatelessWidget {
  const _ReviewEntry({required this.review});

  final ResidentReview review;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  review.author,
                  style: AppTextStyles.ctaSmall.copyWith(
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                ),
                if (review.verifiedResident) const VerifiedBadge(label: '인증'),
                _Stars(score: review.score.round()),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              '“${review.body}”',
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

/// Read-only stars in ink. The count is said once, as a number, rather than
/// as five separate "star" announcements.
class _Stars extends StatelessWidget {
  const _Stars({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '별점 $score점',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= ReviewDraft.maxScore; i++)
            Icon(
              Icons.star_rounded,
              size: 15,
              color: i <= score ? AppColors.ink : AppColors.neutral400,
            ),
        ],
      ),
    );
  }
}

/// The send glyph, named for both systems so the iOS field never carries a
/// Material arrow.
const _sendIcon = AppIcon(Icons.send, 'paperplane.fill');

/// The write action: a compact prominent glass button on iOS, Material 3's
/// extended FAB on Android. Writing is behind the gate, so an unverified
/// resident gets the explanation rather than the page.
class _ComposeAction extends StatelessWidget {
  const _ComposeAction();

  static Future<void> _compose(BuildContext context) async {
    final posted = await context.push<bool>(AppRoutes.reviewCompose);
    if ((posted ?? false) && context.mounted) {
      await PlatformAdaptiveNotice.show(context, message: '평가를 올렸습니다.');
    }
  }

  /// The same action for the native iOS tab bar's accessory.
  static TabAccessory accessory(BuildContext context, WidgetRef ref) {
    return TabAccessory(
      label: '평가 작성',
      icon: AppIcons.write,
      onPressed: () =>
          runVerified(context, ref, onVerified: () => _compose(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return VerifiedGate(
      onVerified: () => _compose(context),
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppPrimaryButton(
            label: '평가 작성',
            icon: AppIcons.write,
            expand: false,
            onPressed: onPressed,
          );
        }

        return AppExtendedFab(
          label: '평가 작성',
          icon: AppIcons.write.material,
          onPressed: onPressed,
        );
      },
    );
  }
}

/// The district channel. The field it is written in floats over the page;
/// this is what it is read in, with the warning at the foot where the next
/// message would land.
class _ChannelTab extends ConsumerWidget {
  const _ChannelTab({required this.notice});

  final String? notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(channelProvider);
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x4,
        AppSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          messages.when(
            loading: () => const InkLoadingRows(rows: 4),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x8),
              child: Center(
                child: Text(
                  error is NotAvailableException
                      ? '지역구 채팅은 아직 준비 중입니다.'
                      : '채팅을 불러오지 못했습니다.',
                ),
              ),
            ),
            // A column rather than a lazy list so each message keeps its
            // element by key: a new message rises in on its own instead of
            // every row re-running its entrance when the list shifts.
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.isEmpty)
                  const _EmptyNote(
                    title: '아직 메시지가 없습니다.',
                    detail: '이 지역구 주소 인증 주민이 보낸 메시지가 여기에 쌓입니다.',
                  ),
                for (var i = 0; i < data.length; i++)
                  RevealIn(
                    key: ValueKey(data[i].id),
                    // Newest first, since the list is read from the bottom.
                    index: data.length - 1 - i,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.x3),
                      child: _Message(message: data[i]),
                    ),
                  ),
              ],
            ),
          ),
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
      ),
    );
  }
}

/// A chat line, kept flat: no fill for others, a tonal neutral for one's own.
/// Alignment says whose it is; colour is not spent on it.
class _Message extends StatelessWidget {
  const _Message({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = BorderRadius.circular(surface.isGlass ? 14 : 4);
    final mine = message.mine;

    final author = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.author,
          style: AppTextStyles.statLabel.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (message.verifiedResident) ...[
          const SizedBox(width: AppSpacing.x1 + 2),
          const VerifiedBadge(label: '인증'),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!mine) ...[author, const SizedBox(height: AppSpacing.x1)],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine ? AppColors.neutral100 : null,
              border: mine ? null : Border.all(color: AppColors.neutral300),
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical: AppSpacing.x2 + 2,
              ),
              child: Text(
                message.body,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.ink,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 「새 메시지」: what arrived below while the reader was scrolled up. It
/// rises in like a message does, and takes the reader down when tapped.
class _NewMessages extends StatelessWidget {
  const _NewMessages({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return RevealIn(
      child: Semantics(
        button: true,
        liveRegion: true,
        label: '새 메시지, 아래로 이동',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          // The pill is drawn small; the target around it is not.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(child: _pill),
          ),
        ),
      ),
    );
  }

  static final Widget _pill = DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x2 - 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.arrow_downward_rounded,
            size: 14,
            color: AppColors.white,
          ),
          const SizedBox(width: AppSpacing.x1),
          Text(
            '새 메시지',
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The message field: a Cupertino text field with a glass send button on
/// iOS, a Material 3 text field with a filled icon button on Android.
///
/// Sending is a write, so it goes through the gate: an unverified resident
/// gets the explanation rather than a dead button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final hint = enabled ? '메시지 보내기' : '주소 인증 주민만 보낼 수 있습니다';

    final send = VerifiedGate(
      onVerified: onSend,
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppToolbarButton(
            icon: _sendIcon,
            label: '보내기',
            onPressed: onPressed,
          );
        }
        // Tonal until the resident is verified: still pressable, since it
        // explains the gate, but not dressed as the page's live action.
        return enabled
            ? IconButton.filled(
                tooltip: '보내기',
                onPressed: onPressed,
                icon: Icon(_sendIcon.material),
              )
            : IconButton.filledTonal(
                tooltip: '보내기',
                onPressed: onPressed,
                icon: Icon(_sendIcon.material),
              );
      },
    );

    if (surface.isGlass) {
      return AppFloatingBar(
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                enabled: enabled,
                placeholder: hint,
                placeholderStyle: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral600,
                ),
                style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? (_) => onSend() : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x4,
                  vertical: AppSpacing.x3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.85),
                  border: Border.all(color: AppColors.neutral300),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            send,
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.ground,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x2,
            AppSpacing.x3,
            AppSpacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? (_) => onSend() : null,
                  decoration: InputDecoration(isDense: true, hintText: hint),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              send,
            ],
          ),
        ),
      ),
    );
  }
}

/// Threads, as a ruled index. Each is opened by an event, and says which.
class _ThreadTab extends ConsumerWidget {
  const _ThreadTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(discussionThreadsProvider);

    return AsyncSection<List<DiscussionThread>>(
      value: threads,
      onRetry: () => ref.invalidate(discussionThreadsProvider),
      builder: (context, data) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.screen,
          AppSpacing.screen,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RevealIn(
              child: DisclaimerBox(
                text:
                    '토론 스레드는 법안 발의와 판정 확정에서 자동으로 열립니다. '
                    '누가 먼저 쓰느냐로 주제가 정해지지 않습니다.',
              ),
            ),
            const SizedBox(height: AppSpacing.x6),
            RevealIn(
              index: 1,
              child: SectionHeader(
                number: '01',
                label: '열린 토론',
                trailing: Text(
                  '${data.length}건',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            if (data.isEmpty)
              const RevealIn(
                index: 2,
                child: _EmptyNote(
                  title: '아직 열린 토론이 없습니다.',
                  detail: '현직 의원이 대표발의한 법안이 수집되면 토론이 자동으로 열립니다.',
                ),
              ),
            for (var i = 0; i < data.length; i++)
              RevealIn(
                key: ValueKey(data[i].id),
                index: i + 2,
                child: _ThreadRow(thread: data[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final DiscussionThread thread;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      minHeight: 64,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.title,
            style: AppTextStyles.reading.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Row(
            children: [
              Expanded(
                child: Text(
                  thread.origin,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                '${thread.replies}개 의견',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
