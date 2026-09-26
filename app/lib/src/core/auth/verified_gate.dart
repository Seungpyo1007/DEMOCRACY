import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef VerifiedActionBuilder =
    Widget Function(BuildContext context, VoidCallback onPressed);

/// Runs [onVerified] for a resident who may write here; otherwise opens the
/// gate sheet. The same check [VerifiedGate] applies, for an action that is
/// not built through it -- the tab bar's accessory.
///
/// "May write" is a residency in this district held by the signed-in
/// account: the address state is reconciled with the account on every
/// sign-in, sign-out and restore, so its verified flag already means that.
void runVerified(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onVerified,
}) {
  if (ref.read(addressControllerProvider).isVerified) {
    onVerified();
    return;
  }
  GateSheet.show(context);
}

class VerifiedGate extends ConsumerWidget {
  const VerifiedGate({
    required this.builder,
    required this.onVerified,
    super.key,
  });

  final VerifiedActionBuilder builder;
  final VoidCallback onVerified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVerified = ref.watch(addressControllerProvider).isVerified;

    return builder(context, () {
      if (isVerified) {
        onVerified();
      } else {
        GateSheet.show(context);
      }
    });
  }
}

/// `글쓰기 전에` -- the three steps between reading and writing, with the
/// one the reader is on marked. Reading is always step one and always done.
class GateSheet extends ConsumerWidget {
  const GateSheet({required this.returnTo, super.key});

  /// Where the reader was, so the steps bring them back to it.
  final String returnTo;

  static Future<void> show(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final returnTo =
        router?.routerDelegate.currentConfiguration.uri.toString() ??
        AppRoutes.home;
    return PlatformAdaptiveSheet.show<void>(
      context: context,
      builder: (context) => GateSheet(returnTo: returnTo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(writeAccessProvider);
    final needsAccount = access == WriteAccess.needsAccount;
    final residency = AppRoutes.withNext(AppRoutes.residency, returnTo);

    void proceed() {
      Navigator.of(context).pop();
      // Signing in continues straight into the residency check, and that
      // returns to the page the gate was opened on.
      context.push(
        needsAccount
            ? AppRoutes.withNext(AppRoutes.login, residency)
            : residency,
      );
    }

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
            const SectionHeader(label: '글쓰기 전에'),
            const SizedBox(height: AppSpacing.x4),
            Text(
              '글은 이 지역구\n주민이 씁니다.',
              style: AppTextStyles.onboardingHeadlineAndroid.copyWith(
                fontSize: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
            const _Step(
              number: '1',
              title: '둘러보기',
              detail: '지금 여기 있어요',
              state: _StepState.done,
            ),
            _Step(
              number: '2',
              title: '계정',
              detail: 'Apple · 카카오 · Google · 이메일',
              state: needsAccount ? _StepState.next : _StepState.done,
            ),
            _Step(
              number: '3',
              title: '주민 인증',
              detail: '주소로 지역구를 한 번 확인, 주소는 폐기',
              state: needsAccount ? _StepState.later : _StepState.next,
            ),
            const SizedBox(height: AppSpacing.x6),
            AppPrimaryButton(
              label: needsAccount ? '로그인하고 계속' : '주민 인증하기',
              onPressed: proceed,
            ),
            const SizedBox(height: AppSpacing.x1),
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

enum _StepState { done, next, later }

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
    required this.state,
  });

  final String number;
  final String title;
  final String detail;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final numberColor = switch (state) {
      _StepState.done => AppColors.neutral600,
      _StepState.next => AppColors.signal,
      _StepState.later => AppColors.neutral500,
    };
    final Widget trailing = switch (state) {
      _StepState.done => const Icon(
        Icons.check,
        size: 20,
        color: AppColors.signal,
        semanticLabel: '완료',
      ),
      _StepState.next => Text(
        '다음',
        style: AppTextStyles.tag.copyWith(
          color: AppColors.signal,
          fontWeight: FontWeight.w700,
        ),
      ),
      _StepState.later => Text(
        '그다음',
        style: AppTextStyles.tag.copyWith(color: AppColors.neutral600),
      ),
    };

    return RuledRow(
      minHeight: 56,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              number,
              style: AppTextStyles.figureSmall.copyWith(
                fontSize: 18,
                color: numberColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.cardBody.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
