import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/features/account/presentation/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `02 처음 오셨네요` -- the first sign-in's only questions.
///
/// Three are required and one is not, and the page says exactly what is and
/// is not collected before anything is accepted. The handle is drawn, not
/// typed: nobody can make themselves look like a candidate.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({this.next, super.key});

  final String? next;

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _age14 = false;
  bool _terms = false;
  bool _privacy = false;
  bool _notify = false;
  bool _saving = false;

  bool get _complete => _age14 && _terms && _privacy;

  Future<void> _accept(String handle) async {
    setState(() => _saving = true);
    await ref
        .read(authControllerProvider.notifier)
        .acceptConsent(
          ConsentInput(
            age14: _age14,
            terms: _terms,
            privacy: _privacy,
            notify: _notify,
            handle: handle,
          ),
        );
    if (mounted) {
      context.go(widget.next ?? AppRoutes.home);
    }
  }

  Future<void> _under14() async {
    await ref.read(authControllerProvider.notifier).declareUnder14();
    if (mounted) {
      context.pushReplacement(AppRoutes.under14);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final handle = state is AuthNeedsConsent && state.handleOptions.isNotEmpty
        ? state.handleOptions.first
        : null;

    return AccountPage(
      title: '처음 오셨네요',
      onBack: _signOutAndLeave(context),
      action: AppPrimaryButton(
        label: _saving ? '저장하는 중' : '동의하고 시작하기',
        onPressed: _complete && handle != null && !_saving
            ? () => _accept(handle)
            : null,
      ),
      children: [
        const SectionHeader(number: '02', label: '처음 오셨네요'),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '몇 가지만 확인할게요.',
          style: Theme.of(context).platform == TargetPlatform.iOS
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x4),
        _ConsentRow(
          label: '만 14세 이상입니다',
          required: true,
          detail:
              '만 14세 미만은 법정대리인 동의가 필요해 지금은 가입할 수 없습니다. '
              '둘러보기는 그대로 쓸 수 있습니다.',
          value: _age14,
          onChanged: (v) => setState(() => _age14 = v),
          trailing: TextLink(
            label: '만 14세 미만이에요',
            small: true,
            onTap: _under14,
          ),
        ),
        _ConsentRow(
          label: '이용약관',
          required: true,
          value: _terms,
          onChanged: (v) => setState(() => _terms = v),
        ),
        _ConsentRow(
          label: '개인정보 수집·이용',
          required: true,
          value: _privacy,
          onChanged: (v) => setState(() => _privacy = v),
        ),
        _ConsentRow(
          label: '공약 이행 기록 알림',
          required: false,
          detail: '내 지역구 공약에 새 기록이 붙을 때만 보냅니다.',
          value: _notify,
          onChanged: (v) => setState(() => _notify = v),
        ),
        const SizedBox(height: AppSpacing.x6),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Column(
                title: '받는 것',
                lines: ['로그인 제공자 식별자', '이메일(제공될 때)', '활동명', '동의 시각·약관 버전'],
              ),
            ),
            SizedBox(width: AppSpacing.x4),
            Expanded(
              child: _Column(
                title: '받지 않는 것',
                lines: ['실명', '전화번호', '생년월일', '주소 원문'],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x6),
        _HandleRow(handle: handle),
      ],
    );
  }

  /// Backing out of consent signs out: an account half-made is not kept
  /// waiting on the device.
  VoidCallback _signOutAndLeave(BuildContext context) => () async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) {
      context.go(AppRoutes.home);
    }
  };
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.label,
    required this.required,
    required this.value,
    required this.onChanged,
    this.detail,
    this.trailing,
  });

  final String label;
  final bool required;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tag = required ? '(필수)' : '(선택)';
    return MergeSemantics(
      child: RuledRow(
        onTap: () => onChanged(!value),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox.adaptive(
              value: value,
              activeColor: AppColors.signal,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.x3),
                  Text.rich(
                    TextSpan(
                      text: '$label ',
                      style: AppTextStyles.cardBody.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: tag,
                          style: const TextStyle(
                            color: AppColors.neutral700,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      detail!,
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.neutral700,
                        height: 1.5,
                      ),
                    ),
                  ],
                  ?trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: title),
        const SizedBox(height: AppSpacing.x2),
        for (final line in lines)
          Text(
            line,
            style: AppTextStyles.statLabel.copyWith(
              fontSize: 13,
              color: AppColors.neutral700,
              height: 1.6,
            ),
          ),
      ],
    );
  }
}

class _HandleRow extends ConsumerWidget {
  const _HandleRow({required this.handle});

  final String? handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '활동명',
          style: AppTextStyles.sectionLabel.copyWith(
            color: AppColors.neutral700,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                handle ?? '',
                style: AppTextStyles.figureSmall.copyWith(fontSize: 24),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).rerollHandles(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.signal,
                minimumSize: const Size(44, 44),
              ),
              child: const Text('다시 뽑기'),
            ),
          ],
        ),
        Text(
          '활동명으로 올릴 때만 이 이름이 보입니다. 익명 게시가 기본입니다.',
          style: AppTextStyles.statLabel.copyWith(
            color: AppColors.neutral700,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Saying "under 14" ends here. The sign-in that was just made is gone and
/// no account was created; reading is untouched.
class Under14Screen extends ConsumerWidget {
  const Under14Screen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void back() {
      ref.read(authControllerProvider.notifier).dismissFailure();
      context.go(AppRoutes.home);
    }

    return AccountPage(
      title: '가입할 수 없어요',
      onBack: back,
      action: AppPrimaryButton(label: '둘러보기로 돌아가기', onPressed: back),
      children: [
        const SectionHeader(label: '가입할 수 없어요'),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '만 14세 미만은\n아직 가입할 수 없습니다.',
          style: Theme.of(context).platform == TargetPlatform.iOS
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x3),
        const LeadText(
          '만 14세 미만의 개인정보를 받으려면 법정대리인의 동의가 필요합니다. '
          'DEMOCRACY는 아직 그 절차를 갖추지 않았습니다.',
        ),
        const SizedBox(height: AppSpacing.x6),
        const Divider(height: 1, color: AppColors.divider),
        const FactRow(label: '지운 것', value: '방금 받은 로그인 정보. 계정은 만들어지지 않았습니다.'),
        const FactRow(
          label: '그대로 볼 수 있는 것',
          value: '지역구 정보, 선거 역사, 공약 기록, 주민 리뷰',
        ),
      ],
    );
  }
}
