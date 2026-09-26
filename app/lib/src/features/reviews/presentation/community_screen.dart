import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
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

  ContentWarning? _warning;
  bool _acknowledged = false;

  @override
  void dispose() {
    _scroll.dispose();
    _message.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _tab) {
      return;
    }
    PlatformAdaptiveHaptics.selection();
    setState(() => _tab = index);
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
    final warning = ContentGuard.inspect(body);
    if (warning != null && !_acknowledged) {
      setState(() {
        _warning = warning;
        _acknowledged = true;
      });
      _revealLatest();
      return;
    }

    final district = ref.read(addressControllerProvider).district;
    if (district == null) {
      return;
    }

    await ref.read(communityRepositoryProvider).send(district.id, body);
    _message.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _warning = null;
      _acknowledged = false;
    });
    _revealLatest();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final verified = ref.watch(addressControllerProvider).isVerified;

    // The channel's field is a bar across the foot; the review tab's write
    // action is a compact floating button, placed as the tracker's is.
    final composer = _tab == 1
        ? _Composer(controller: _message, enabled: verified, onSend: _send)
        : null;

    return TabAccessoryScope(
      slot: TabSlot.community,
      // Only the reviews pane has a single primary action to lend.
      accessory: _tab == 0 && usesNativeIosControls(context)
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
                floatingAction: _tab == 0 && !usesNativeIosControls(context)
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
                          1 => _ChannelTab(warning: _warning),
                          _ => const _ThreadTab(),
                        },
                      ),
                    ),
                  ),
                ],
              ),
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
            RevealIn(child: _Summary(summary: data.summary)),
            const SizedBox(height: 18),
            const RevealIn(
              index: 1,
              child: DisclaimerBox(
                text:
                    '주소 인증 주민만 작성 가능 · 조작 방지 알고리즘 · '
                    '혐오·허위정보 자동 필터링',
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
  const _ChannelTab({required this.warning});

  final ContentWarning? warning;

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
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x8),
              child: Center(child: PlatformAdaptiveProgress.circular(context)),
            ),
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
            child: warning == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.x4),
                    child: Semantics(
                      liveRegion: true,
                      child: DisclaimerBox(
                        text: '${warning!.message} 그대로 보내려면 한 번 더 누르세요.',
                      ),
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
