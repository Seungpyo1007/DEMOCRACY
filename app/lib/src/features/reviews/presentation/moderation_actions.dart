import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/reviews/application/moderation_providers.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The 「…」 on someone else's review or message: 신고하기, 이 주민 글 숨기기.
///
/// Not shown on the reader's own posts or on a post already hidden. Both
/// need an account (not a residency: a reader of any district can report
/// what they read); signed out, the reader is offered sign-in first.
class PostMenu extends ConsumerWidget {
  const PostMenu({required this.kind, required this.postId, super.key});

  final PostKind kind;
  final String postId;

  static const _items = [
    AppMenuItem(label: '신고하기', icon: AppIcon(Icons.flag_outlined, 'flag')),
    AppMenuItem(
      label: '이 주민 글 숨기기',
      icon: AppIcon(Icons.visibility_off_outlined, 'eye.slash'),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppMenuButton(
      key: ValueKey('post-menu-$postId'),
      icon: const AppIcon(Icons.more_horiz, 'ellipsis'),
      semanticLabel: '글 메뉴',
      items: _items,
      onSelected: (i) => i == 0
          ? reportPost(context, ref, kind, postId)
          : blockAuthor(context, ref, kind, postId),
    );
  }
}

/// Signed in, or offered sign-in and false.
Future<bool> _signedIn(BuildContext context, WidgetRef ref, String what) async {
  if (ref.read(authControllerProvider) is AuthSignedIn) {
    return true;
  }
  final router = GoRouter.maybeOf(context);
  final here = router?.routerDelegate.currentConfiguration.uri.toString();
  await PlatformAdaptiveDialog.show(
    context: context,
    title: '로그인이 필요합니다',
    message: '$what 하려면 로그인하세요. 주민 인증은 필요 없습니다.',
    confirmLabel: '로그인',
    onConfirmed: () => router?.push(AppRoutes.withNext(AppRoutes.login, here)),
    secondaryLabel: '취소',
  );
  return false;
}

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(reviewBoardProvider)
    ..invalidate(channelProvider);
}

Future<void> _settle(BuildContext context, WidgetRef ref, Object error) async {
  if (error is SessionExpiredException) {
    await ref.read(authControllerProvider.notifier).sessionExpired();
    return;
  }
  if (!context.mounted) return;
  await PlatformAdaptiveNotice.show(
    context,
    message: error is ModerationException
        ? error.message
        : ModerationException.generic.message,
  );
}

Future<void> reportPost(
  BuildContext context,
  WidgetRef ref,
  PostKind kind,
  String postId,
) async {
  if (!await _signedIn(context, ref, '신고') || !context.mounted) return;
  final choice = await PlatformAdaptiveSheet.show<(ReportReason, String)>(
    context: context,
    builder: (context) => const ReportSheet(),
  );
  if (choice == null || !context.mounted) return;
  try {
    final outcome = await ref
        .read(moderationRepositoryProvider)
        .report(kind, postId, choice.$1, note: choice.$2);
    _refresh(ref);
    if (!context.mounted) return;
    await PlatformAdaptiveNotice.show(
      context,
      message: outcome == ReportOutcome.hidden
          ? '신고했습니다. 이 글은 지금부터 가려집니다.'
          : '신고했습니다. 운영자가 확인합니다.',
    );
  } on Object catch (error) {
    if (context.mounted) await _settle(context, ref, error);
  }
}

Future<void> blockAuthor(
  BuildContext context,
  WidgetRef ref,
  PostKind kind,
  String postId,
) async {
  if (!await _signedIn(context, ref, '숨기기') || !context.mounted) return;
  var confirmed = false;
  await PlatformAdaptiveDialog.show(
    context: context,
    title: '이 주민의 글을 숨길까요?',
    message:
        '내 화면에서만 사라집니다. 상대에게는 알리지 않고, '
        '내 계정 → 숨긴 주민에서 되돌릴 수 있습니다.',
    confirmLabel: '숨기기',
    onConfirmed: () => confirmed = true,
    secondaryLabel: '취소',
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ref.read(moderationRepositoryProvider).block(kind, postId);
    ref.invalidate(blocksProvider);
    _refresh(ref);
    if (!context.mounted) return;
    await PlatformAdaptiveNotice.show(context, message: '이 주민의 글을 숨겼습니다.');
  } on Object catch (error) {
    if (context.mounted) await _settle(context, ref, error);
  }
}

/// Picks a reason and, optionally, a short note. Pops (reason, note).
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x4,
          AppSpacing.screen,
          AppSpacing.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(label: '신고하기'),
            const SizedBox(height: AppSpacing.x2),
            Text(
              '신고한 사람은 글쓴이에게 알려지지 않습니다.',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral700,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            for (final r in ReportReason.values)
              Semantics(
                selected: r == reason,
                button: true,
                child: RuledRow(
                  key: ValueKey('report-${r.wire}'),
                  onTap: () => setState(() => _reason = r),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.label, style: AppTextStyles.cardBody),
                            if (r.detail != null)
                              Text(
                                r.detail!,
                                style: AppTextStyles.statLabel.copyWith(
                                  color: AppColors.neutral600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        r == reason
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 22,
                        color: r == reason
                            ? AppColors.ink
                            : AppColors.neutral500,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.x4),
            TextField(
              controller: _note,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '덧붙일 말 (선택)',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            AppPrimaryButton(
              label: '신고하기',
              onPressed: reason == null
                  ? null
                  : () => Navigator.of(context).pop((reason, _note.text)),
            ),
          ],
        ),
      ),
    );
  }
}
