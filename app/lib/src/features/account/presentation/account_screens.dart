import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/app/app_version.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/account_repository.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/account/device_services.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/account/presentation/account_page.dart';
import 'package:democracy/src/features/account/presentation/residency_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void _back(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.home);
  }
}

/// `내 계정` -- four numbered sections. Residency sits apart from the account
/// on purpose: they are managed separately, and the page says so.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    if (state is! AuthSignedIn) {
      // The router keeps a signed-out reader off this page; this covers the
      // frame between signing out and the redirect.
      return const Scaffold(body: SizedBox.shrink());
    }
    final account = state.account;
    final residency = state.residency;
    final now = ref.watch(clockProvider).now().utc;
    final confirm = ref.watch(deviceConfirmProvider);

    Future<void> signOut() => PlatformAdaptiveDialog.show(
      context: context,
      title: '로그아웃할까요?',
      message:
          '이 기기에서만 로그아웃됩니다. 내 지역구는 남아 있어 계속 둘러볼 수 있고, '
          '주민 인증과 활동명은 다시 로그인하면 돌아옵니다.',
      confirmLabel: '로그아웃',
      secondaryLabel: '취소',
      onConfirmed: () async {
        await ref.read(authControllerProvider.notifier).signOut();
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
      },
    );

    return AccountPage(
      title: '내 계정',
      onBack: () => _back(context),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSecondaryButton(label: '로그아웃', onPressed: signOut),
          TextButton(
            onPressed: () => context.push(AppRoutes.accountDelete),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.systemError,
              minimumSize: const Size(44, 48),
            ),
            child: const Text('계정 삭제'),
          ),
        ],
      ),
      children: [
        const SectionHeader(number: '01', label: '계정'),
        _ValueRow(label: '로그인 방식', value: account.provider.label),
        _ValueRow(
          label: '활동명',
          value: account.handle,
          serif: true,
          action: TextLink(label: '변경', onTap: () => HandleSheet.show(context)),
        ),
        _ValueRow(label: '이메일', value: account.email ?? '받지 않음'),
        const SizedBox(height: AppSpacing.x8),
        const SectionHeader(
          number: '02',
          label: '주민 인증',
          trailing: _Aside('계정과 따로 관리됩니다'),
        ),
        if (residency != null && residency.isValidAt(now)) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x4),
            child: Row(
              children: [
                const VerifiedBadge(label: '인증됨'),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  ResidencyDoneScreen.date(residency.verifiedAt),
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            residency.displayName,
            style: AppTextStyles.figureSmall.copyWith(fontSize: 24),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            '입력한 주소는 인증 직후 폐기했습니다. 남아 있는 것은 지역구와 인증 날짜뿐입니다.',
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral700,
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          const Divider(height: 1, color: AppColors.divider),
          _LinkRow(
            label: '이사했어요 · 지역구 다시 인증',
            onTap: () => context.push(
              AppRoutes.withNext(AppRoutes.residency, AppRoutes.account),
            ),
          ),
        ] else
          _LinkRow(
            label: residency == null ? '아직 인증하지 않았어요 · 인증하기' : '만료됐어요 · 다시 인증',
            onTap: () => context.push(
              AppRoutes.withNext(AppRoutes.residency, AppRoutes.account),
            ),
          ),
        const SizedBox(height: AppSpacing.x8),
        const SectionHeader(number: '03', label: '이 기기'),
        RuledRow(
          minHeight: 60,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('중요한 작업은 기기 인증으로 확인', style: AppTextStyles.cardBody),
                    Text(
                      '계정 삭제 전. 거주지 증명은 아닙니다.',
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.neutral700,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: confirm,
                semanticLabel: '중요한 작업은 기기 인증으로 확인',
                onChanged: (value) => ref
                    .read(deviceConfirmProvider.notifier)
                    .set(enabled: value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x8),
        const SectionHeader(number: '04', label: '내 기록'),
        _LinkRow(
          label: '내 데이터 내려받기',
          onTap: () => context.push(AppRoutes.accountExport),
        ),
        RuledRow(
          minHeight: 60,
          child: Row(
            children: [
              Expanded(
                child: Text('공약 이행 기록 알림', style: AppTextStyles.cardBody),
              ),
              AppSwitch(
                value: account.notify,
                semanticLabel: '공약 이행 기록 알림',
                onChanged: (value) => ref
                    .read(authControllerProvider.notifier)
                    .setNotify(notify: value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x8),
        const SectionHeader(number: '05', label: '앱 정보'),
        const _ValueRow(label: '버전', value: '$appVersion ($appBuild)'),
        _LinkRow(
          label: '오픈소스 라이선스',
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'DEMOCRACY',
            applicationVersion: '$appVersion ($appBuild)',
          ),
        ),
      ],
    );
  }
}

class _Aside extends StatelessWidget {
  const _Aside(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral700),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.serif = false,
    this.action,
  });

  final String label;
  final String value;
  final bool serif;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      minHeight: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral700,
              ),
            ),
          ),
          Text(
            value,
            style: serif
                ? AppTextStyles.figureSmall.copyWith(fontSize: 17)
                : AppTextStyles.cardBody,
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.x3),
            action!,
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      minHeight: 52,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.cardBody)),
          const Icon(Icons.chevron_right, color: AppColors.neutral600),
        ],
      ),
    );
  }
}

/// `활동명 바꾸기` -- picked from drawn names, never typed, at most once in
/// 30 days. The limit is the server's; the sheet only reports it.
class HandleSheet extends ConsumerStatefulWidget {
  const HandleSheet({super.key});

  static Future<void> show(BuildContext context) =>
      PlatformAdaptiveSheet.show<void>(
        context: context,
        builder: (context) => const HandleSheet(),
      );

  @override
  ConsumerState<HandleSheet> createState() => _HandleSheetState();
}

class _HandleSheetState extends ConsumerState<HandleSheet> {
  late Future<List<String>> _options = _draw();
  String? _picked;
  bool _saving = false;

  Future<List<String>> _draw() =>
      ref.read(authControllerProvider.notifier).handleOptions();

  Future<void> _save(String handle) async {
    setState(() => _saving = true);
    await ref.read(authControllerProvider.notifier).claimHandle(handle);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x4,
          AppSpacing.screen,
          AppSpacing.x4,
        ),
        child: FutureBuilder<List<String>>(
          future: _options,
          builder: (context, snapshot) {
            final error = snapshot.error;
            if (error is HandleTooSoonException) {
              final at = error.availableAt;
              return _SheetMessage(
                title: '아직 바꿀 수 없어요',
                body: at == null
                    ? '활동명은 30일에 한 번 바꿀 수 있습니다.'
                    : '활동명은 30일에 한 번 바꿀 수 있습니다. '
                          '${ResidencyDoneScreen.date(at)}부터 다시 바꿀 수 있어요.',
              );
            }
            final options = snapshot.data;
            if (options == null) {
              return const InkLoadingRows();
            }
            final picked = _picked ?? options.first;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(label: '활동명 바꾸기'),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  '새 활동명을 고르세요.',
                  style: AppTextStyles.onboardingHeadlineAndroid.copyWith(
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                const LeadText(
                  '활동명은 직접 짓지 않고 목록에서 고릅니다. 후보나 의원을 사칭하는 이름을 막기 위해서입니다.',
                ),
                const SizedBox(height: AppSpacing.x3),
                RadioGroup<String>(
                  groupValue: picked,
                  onChanged: (value) => setState(() => _picked = value),
                  child: Column(
                    children: [
                      for (final option in options)
                        RuledRow(
                          minHeight: 52,
                          onTap: () => setState(() => _picked = option),
                          child: Row(
                            children: [
                              Radio<String>.adaptive(value: option),
                              const SizedBox(width: AppSpacing.x2),
                              Text(
                                option,
                                style: AppTextStyles.figureSmall.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _picked = null;
                      _options = _draw();
                    }),
                    child: const Text('다른 이름 보기'),
                  ),
                ),
                Text(
                  '30일에 한 번 바꿀 수 있습니다. 이미 활동명으로 올린 글에도 새 이름이 표시됩니다.',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                AppPrimaryButton(
                  label: _saving ? '바꾸는 중' : '$picked로 바꾸기',
                  onPressed: _saving ? null : () => _save(picked),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: title),
        const SizedBox(height: AppSpacing.x4),
        LeadText(body),
        const SizedBox(height: AppSpacing.x6),
        AppPrimaryButton(
          label: '확인',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// `내 데이터 내려받기` -- everything the server holds, as one JSON file.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _working = false;

  Future<void> _export() async {
    setState(() => _working = true);
    try {
      final export = await ref.read(authControllerProvider.notifier).export();
      await ref.read(exportSharerProvider).share(export);
    } on Object {
      if (mounted) {
        await PlatformAdaptiveNotice.show(
          context,
          message: '파일을 만들지 못했어요. 잠시 뒤 다시 시도하세요.',
        );
      }
    }
    if (mounted) {
      setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: '내 데이터 내려받기',
      onBack: () => _back(context),
      action: AppPrimaryButton(
        label: _working ? '만드는 중' : '파일 만들기',
        onPressed: _working ? null : _export,
      ),
      children: const [
        SectionHeader(label: '내 데이터 내려받기'),
        SizedBox(height: AppSpacing.x6),
        LeadText('내 기록을 파일 하나로 받습니다.'),
        SizedBox(height: AppSpacing.x6),
        Divider(height: 1, color: AppColors.divider),
        FactRow(
          label: '들어가는 것',
          value: '로그인 방식, 활동명, 가입일\n동의 기록(항목, 시각, 약관 버전)\n주민 인증 기록(지역구, 날짜)',
        ),
        FactRow(label: '없는 것', value: '주소 원문과 좌표. 처음부터 보관하지 않았습니다.'),
        FactRow(label: '형식', value: 'JSON 파일 하나. 공유 시트로 저장하거나 보냅니다.'),
      ],
    );
  }
}

/// `계정 삭제` -- immediate, after the device confirms it is the owner.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _deletePosts = false;
  bool _working = false;

  Future<void> _delete() async {
    if (ref.read(deviceConfirmProvider)) {
      final ok = await ref
          .read(deviceAuthProvider)
          .authenticate(reason: '계정을 삭제하려면 본인 기기임을 확인하세요.');
      if (!ok) {
        return;
      }
    }
    setState(() => _working = true);
    await ref
        .read(authControllerProvider.notifier)
        .deleteAccount(deletePosts: _deletePosts);
    if (mounted) {
      context.go(AppRoutes.home);
      await PlatformAdaptiveNotice.show(context, message: '계정을 삭제했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirm = ref.watch(deviceConfirmProvider);
    return AccountPage(
      title: '계정 삭제',
      onBack: () => _back(context),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (confirm)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x2),
              child: Text(
                '기기 인증으로 확인한 뒤 삭제합니다.',
                textAlign: TextAlign.center,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ActionTint(
            color: AppColors.systemError,
            child: AppPrimaryButton(
              label: _working ? '삭제하는 중' : '계정 삭제',
              onPressed: _working ? null : _delete,
            ),
          ),
        ],
      ),
      children: [
        const SectionHeader(label: '계정 삭제'),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '삭제하면\n되돌릴 수 없습니다.',
          style: Theme.of(context).platform == TargetPlatform.iOS
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x6),
        const Divider(height: 1, color: AppColors.divider),
        const FactRow(label: '바로 삭제', value: '계정, 활동명, 알림 설정, 주민 인증 기록'),
        const FactRow(
          label: '남는 것',
          value: '이미 올린 리뷰는 작성자 연결을 끊고 「탈퇴한 주민」으로 남습니다. 아래에서 함께 지울 수 있습니다.',
        ),
        const SizedBox(height: AppSpacing.x3),
        MergeSemantics(
          child: InkWell(
            onTap: () => setState(() => _deletePosts = !_deletePosts),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Checkbox.adaptive(
                    value: _deletePosts,
                    activeColor: AppColors.systemError,
                    onChanged: (v) => setState(() => _deletePosts = v ?? false),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Text('내가 쓴 리뷰와 제보도 모두 삭제', style: AppTextStyles.cardBody),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sheet shown when the server refuses the session mid-use. Whatever was
/// being written stays on its page, under the sign-in.
class SessionExpiredSheet extends StatelessWidget {
  const SessionExpiredSheet({required this.returnTo, super.key});

  final String returnTo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x4,
          AppSpacing.screen,
          AppSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(label: '로그인 만료'),
            const SizedBox(height: AppSpacing.x4),
            Text(
              '다시 로그인하면\n이어서 올릴 수 있어요.',
              style: AppTextStyles.onboardingHeadlineAndroid.copyWith(
                fontSize: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            const LeadText(
              '오래 쓰지 않아 로그인이 끝났습니다. 쓰던 글은 이 화면에 그대로 있고, '
              '올리기 전에는 아무 데도 보내지 않았습니다.',
            ),
            const SizedBox(height: AppSpacing.x6),
            AppPrimaryButton(
              label: '다시 로그인',
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.withNext(AppRoutes.login, returnTo));
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.neutral700,
                minimumSize: const Size(44, 48),
              ),
              child: const Text('나중에'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [SessionExpiredSheet] whenever the account is signed out by the
/// server rather than by the person.
class SessionExpiryListener extends ConsumerWidget {
  const SessionExpiryListener({
    required this.navigatorKey,
    required this.currentLocation,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final String Function() currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authControllerProvider, (previous, next) {
      final navigatorContext = navigatorKey.currentContext;
      if (next is AuthSignedOut &&
          next.sessionExpired &&
          previous is! AuthSignedOut &&
          navigatorContext != null) {
        PlatformAdaptiveSheet.show<void>(
          context: navigatorContext,
          builder: (_) => SessionExpiredSheet(returnTo: currentLocation()),
        );
      }
    });
    return child;
  }
}

/// The home header's way into the account: an outline figure when signed
/// out, a filled one when signed in.
class AccountEntryButton extends ConsumerWidget {
  const AccountEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Account? account = ref.watch(authControllerProvider).account;
    return AppToolbarButton(
      icon: account == null ? AppIcons.person : AppIcons.personFilled,
      label: account == null ? '로그인' : '내 계정 · ${account.handle}',
      onPressed: () =>
          context.push(account == null ? AppRoutes.login : AppRoutes.account),
    );
  }
}
