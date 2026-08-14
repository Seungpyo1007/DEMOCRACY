import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/labeled_bar.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/review_compose_sheet.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Ratings, the channel and the threads, in one district hub.
///
/// Three tabs rather than three destinations because they are three ways of
/// saying the same thing about the same seat, and splitting them across the
/// bottom bar would make the district look like three communities.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final district = ref.watch(addressControllerProvider).district;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: AppSpacing.screen,
          title: Text(
            '${district?.displayName ?? '지역구'} 커뮤니티',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          bottom: TabBar(
            labelPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3 + 2,
            ),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorColor: AppColors.signal,
            dividerColor: AppColors.neutral200,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.neutral600,
            labelStyle: AppTextStyles.tabLabel,
            unselectedLabelStyle: AppTextStyles.tabLabel,
            tabs: const [
              Tab(height: 38, text: '주민 평가'),
              Tab(height: 38, text: '지역 채팅'),
              Tab(height: 38, text: '정책 토론'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ReviewTab(), _ChannelTab(), _ThreadTab()],
        ),
      ),
    );
  }
}

class _ReviewTab extends ConsumerWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(reviewBoardProvider);

    return Column(
      children: [
        Expanded(
          child: AsyncSection<ReviewBoard>(
            value: board,
            onRetry: () => ref.invalidate(reviewBoardProvider),
            builder: (context, data) => ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x3,
                AppSpacing.screen,
                AppSpacing.x4,
              ),
              children: [
                _SummaryCard(summary: data.summary),
                const SizedBox(height: AppSpacing.x3),
                for (final review in data.reviews) ...[
                  _ReviewCard(review: review),
                  const SizedBox(height: AppSpacing.x2 + 2),
                ],
                const DisclaimerBox(
                  text:
                      '평가는 주소 인증 주민만 작성 가능 · 조작 방지 알고리즘 적용 · '
                      '혐오·허위정보 자동 필터링',
                ),
              ],
            ),
          ),
        ),
        const _ComposeAction(),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                summary.averageDisplay,
                style: AppTextStyles.ratingDisplay.copyWith(
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  summary.respondentsDisplay,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          for (final axis in summary.axes) ...[
            LabeledBar(
              label: axis.label,
              fraction: axis.score / 5,
              valueText: axis.display,
              labelWidth: 44,
              valueWidth: 24,
              trackHeight: 7,
            ),
            const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final ResidentReview review;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3 + 2,
        vertical: AppSpacing.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                review.author,
                style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
              ),
              if (review.verifiedResident) ...[
                const SizedBox(width: AppSpacing.x2),
                const VerifiedBadge(label: '인증'),
              ],
              const Spacer(),
              Text(
                '${review.score.toStringAsFixed(1)} / 5',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            review.body,
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral800),
          ),
        ],
      ),
    );
  }
}

class _ComposeAction extends ConsumerWidget {
  const _ComposeAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return VerifiedGate(
      onVerificationRequested: () => context.go(AppRoutes.onboarding),
      onVerified: () async {
        final posted = await ReviewComposeSheet.show(context);
        if (posted ?? false) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('평가를 올렸습니다.')));
          }
        }
      },
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppFloatingBar(
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.x2 + 2),
                Expanded(
                  child: Text(
                    '작성 시 익명 여부를 고를 수 있습니다',
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
                AppPrimaryButton(
                  label: '평가 작성하기',
                  expand: false,
                  onPressed: onPressed,
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.x4,
            AppSpacing.x4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppExtendedFab(
                label: '평가 작성',
                icon: Icons.edit_outlined,
                onPressed: onPressed,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The district channel.
class _ChannelTab extends ConsumerStatefulWidget {
  const _ChannelTab();

  @override
  ConsumerState<_ChannelTab> createState() => _ChannelTabState();
}

class _ChannelTabState extends ConsumerState<_ChannelTab> {
  final _controller = TextEditingController();

  ContentWarning? _warning;
  bool _acknowledged = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
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
      return;
    }

    final district = ref.read(addressControllerProvider).district;
    if (district == null) {
      return;
    }

    await ref.read(communityRepositoryProvider).send(district.id, body);
    _controller.clear();
    setState(() {
      _warning = null;
      _acknowledged = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(channelProvider);
    final verified = ref.watch(addressControllerProvider).isVerified;

    return Column(
      children: [
        Expanded(
          child: messages.when(
            loading: () =>
                Center(child: PlatformAdaptiveProgress.circular(context)),
            error: (error, _) => const Center(child: Text('채팅을 불러오지 못했습니다.')),
            data: (data) => ListView.separated(
              reverse: true,
              padding: const EdgeInsets.all(AppSpacing.screen),
              itemCount: data.length,
              separatorBuilder: (context, _) =>
                  const SizedBox(height: AppSpacing.x2),
              itemBuilder: (context, index) =>
                  _Message(message: data[data.length - 1 - index]),
            ),
          ),
        ),
        if (_warning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.x2,
            ),
            child: DisclaimerBox(
              text: '${_warning!.message} 그대로 보내려면 한 번 더 누르세요.',
            ),
          ),
        _Composer(controller: _controller, enabled: verified, onSend: _send),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x2 + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.author,
                    style: AppTextStyles.statLabel.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                  if (message.verifiedResident) ...[
                    const SizedBox(width: AppSpacing.x1),
                    const VerifiedBadge(label: '인증'),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                message.body,
                style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          AppSpacing.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: enabled ? '메시지 보내기' : '주소 인증 주민만 보낼 수 있습니다',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            IconButton(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
              color: AppColors.signal,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTab extends ConsumerWidget {
  const _ThreadTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(discussionThreadsProvider);

    return AsyncSection<List<DiscussionThread>>(
      value: threads,
      onRetry: () => ref.invalidate(discussionThreadsProvider),
      builder: (context, data) => ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const DisclaimerBox(
            text:
                '토론 스레드는 법안 발의와 판정 확정에서 자동으로 열립니다. '
                '누가 먼저 쓰느냐로 주제가 정해지지 않습니다.',
          ),
          const SizedBox(height: AppSpacing.x4),
          for (final thread in data) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3 + 2,
                vertical: AppSpacing.x3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        thread.origin,
                        style: AppTextStyles.statLabel.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                      Text(
                        '${thread.replies}개 의견',
                        style: AppTextStyles.statLabel.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
        ],
      ),
    );
  }
}
