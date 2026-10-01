import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/features/account/presentation/account_page.dart';
import 'package:democracy/src/features/account/presentation/residency_screens.dart';
import 'package:democracy/src/features/reviews/application/moderation_providers.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `숨긴 주민` -- the authors the reader blocked, as each showed when blocked
/// (a 활동명, or 익명 주민 with the date), and a way to show them again.
class BlockedAuthorsScreen extends ConsumerWidget {
  const BlockedAuthorsScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    BlockedAuthor block,
  ) async {
    try {
      await ref.read(moderationRepositoryProvider).unblock(block.id);
    } on Object {
      if (context.mounted) {
        await PlatformAdaptiveNotice.show(
          context,
          message: ModerationException.generic.message,
        );
      }
      return;
    }
    ref
      ..invalidate(blocksProvider)
      ..invalidate(reviewBoardProvider)
      ..invalidate(channelProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    return AccountPage(
      title: '숨긴 주민',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(AppRoutes.account),
      children: [
        const SectionHeader(label: '숨긴 주민'),
        const SizedBox(height: AppSpacing.x4),
        const LeadText('이 주민들의 평가와 채팅은 내 화면에만 보이지 않습니다. 상대에게는 알리지 않습니다.'),
        const SizedBox(height: AppSpacing.x4),
        AsyncSection<List<BlockedAuthor>>(
          value: blocks,
          onRetry: () => ref.invalidate(blocksProvider),
          builder: (context, data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
                  child: Text(
                    '숨긴 주민이 없습니다.',
                    style: AppTextStyles.cardBody.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ),
              for (final block in data)
                RuledRow(
                  key: ValueKey('blocked-${block.id}'),
                  minHeight: 60,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(block.label, style: AppTextStyles.cardBody),
                            Text(
                              '${ResidencyDoneScreen.date(block.createdAt)} 숨김',
                              style: AppTextStyles.statLabel.copyWith(
                                color: AppColors.neutral600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextLink(
                        label: '다시 보기',
                        onTap: () => _unblock(context, ref, block),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
