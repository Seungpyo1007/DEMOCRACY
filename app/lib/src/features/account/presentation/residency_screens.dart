import 'dart:async';

import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/network/bff_client.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/account/presentation/account_page.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
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

/// `03 주민 인증` -- what is checked, kept and thrown away, before anything
/// is typed.
///
/// The method is named for what it is: the resident says where they live
/// and the server checks that the address is in the district. It does not
/// prove anyone lives there, and the page does not claim it does.
class ResidencyStartScreen extends StatelessWidget {
  const ResidencyStartScreen({this.next, super.key});

  final String? next;

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: '주민 인증',
      onBack: () => _back(context),
      action: AppPrimaryButton(
        label: '주소로 인증 시작',
        onPressed: () =>
            context.push(AppRoutes.withNext(AppRoutes.residencyAddress, next)),
      ),
      children: [
        const SectionHeader(number: '03', label: '주민 인증'),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '이 지역구 주민인지\n한 번 확인합니다.',
          style: Theme.of(context).platform == TargetPlatform.iOS
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x6),
        const Divider(height: 1, color: AppColors.divider),
        const FactRow(label: '확인하는 것', value: '주소가 어느 선거구에 속하는지'),
        const FactRow(label: '남기는 것', value: '선거구, 인증 날짜, 만료일'),
        const FactRow(label: '버리는 것', value: '주소 원문과 좌표. 확인이 끝나는 즉시'),
        const SizedBox(height: AppSpacing.x6),
        const _MethodNote(),
      ],
    );
  }
}

class _MethodNote extends StatelessWidget {
  const _MethodNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral500),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '인증 방식',
              style: AppTextStyles.sectionLabel.copyWith(
                color: AppColors.neutral700,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '주소 확인 · 자기 신고',
              style: AppTextStyles.figureSmall.copyWith(fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '입력한 주소가 이 지역구 안에 있는지 확인합니다. 실거주를 증명하지는 '
              '않습니다. 실명 확인이나 휴대폰 본인인증은 쓰지 않습니다.',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral700,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Finds the resident's address. Only suggestions the district map can place
/// are listed; picking one sends it once to the server, which answers with a
/// district and forgets it. The screen forgets it too.
class ResidencyAddressScreen extends ConsumerStatefulWidget {
  const ResidencyAddressScreen({this.next, super.key});

  final String? next;

  @override
  ConsumerState<ResidencyAddressScreen> createState() =>
      _ResidencyAddressScreenState();
}

class _ResidencyAddressScreenState
    extends ConsumerState<ResidencyAddressScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<AddressSuggestion> _results = const [];
  String? _problem;
  bool _checking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = text.trim();
      if (query.length < 2) {
        setState(() => _results = const []);
        return;
      }
      try {
        final found = await ref
            .read(addressSearchRepositoryProvider)
            .search(query);
        if (mounted) {
          setState(() {
            _results = found;
            _problem = null;
          });
        }
      } on Object {
        if (mounted) {
          setState(() => _problem = '검색하지 못했어요. 잠시 뒤 다시 시도하세요.');
        }
      }
    });
  }

  Future<void> _verify(AddressSuggestion suggestion) async {
    setState(() {
      _checking = true;
      _problem = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyResidency(roadAddress: suggestion.address);
      // The address leaves the screen with the request.
      _query.clear();
      _results = const [];
      if (mounted) {
        context.pushReplacement(
          AppRoutes.withNext(AppRoutes.residencyDone, widget.next),
        );
      }
    } on NotAvailableException {
      _fail('이 주소로는 선거구를 확인할 수 없어요. 도로명과 건물번호까지 넣어 보세요.');
    } on BffException catch (error) {
      _fail(
        error.code == 'no_match'
            ? '이 주소로는 선거구를 확인할 수 없어요. 도로명과 건물번호까지 넣어 보세요.'
            : '확인하지 못했어요. 잠시 뒤 다시 시도하세요.',
      );
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _checking = false;
        _problem = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: '주소 찾기',
      onBack: () => _back(context),
      children: [
        AppSearchField(
          controller: _query,
          placeholder: '도로명 주소 검색',
          onChanged: _search,
        ),
        const SizedBox(height: AppSpacing.x6),
        SectionHeader(
          label: '검색 결과',
          trailing: Text(
            '선거구가 확인된 주소만',
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral700,
            ),
          ),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x3),
            child: ShakeOnce(
              child: Text(
                _problem!,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.systemError,
                ),
              ),
            ),
          ),
        for (final suggestion in _results)
          RuledRow(
            onTap: _checking ? null : () => _verify(suggestion),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.address, style: AppTextStyles.cardBody),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  suggestion.district.displayName,
                  style: AppTextStyles.ctaSmall.copyWith(
                    fontSize: 13,
                    color: AppColors.signal,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '찾는 주소가 없다면 한 동네가 두 선거구로 나뉘는 곳일 수 있습니다. '
          '도로명과 건물번호까지 넣어 다시 찾아보세요.\n검색어는 저장하지 않습니다.',
          style: AppTextStyles.statLabel.copyWith(
            color: AppColors.neutral700,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

/// Done: the district, when it was checked and when it must be again.
class ResidencyDoneScreen extends ConsumerWidget {
  const ResidencyDoneScreen({this.next, super.key});

  final String? next;

  static String date(DateTime at) {
    final kst = at.toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${kst.year}.${two(kst.month)}.${two(kst.day)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final Residency? residency = state is AuthSignedIn ? state.residency : null;

    return AccountPage(
      title: '주민 인증 완료',
      onBack: () => context.go(next ?? AppRoutes.home),
      action: AppPrimaryButton(
        label: next == null || next == AppRoutes.home ? '홈으로' : '쓰던 곳으로 돌아가기',
        onPressed: () => context.go(next ?? AppRoutes.home),
      ),
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: _DoneMark(),
        ),
        const SizedBox(height: AppSpacing.x6),
        const SectionHeader(label: '주민 인증 완료'),
        const SizedBox(height: AppSpacing.x6),
        Text(
          '${residency?.displayName ?? ''}\n주민으로 인증했습니다.',
          style: Theme.of(context).platform == TargetPlatform.iOS
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MarginNote('주소는 방금 지웠어요', underline: false),
        ),
        const SizedBox(height: AppSpacing.x4),
        const Divider(height: 1, color: AppColors.divider),
        if (residency != null) ...[
          FactRow(label: '인증한 날', value: date(residency.verifiedAt)),
          FactRow(label: '다시 확인할 날', value: date(residency.expiresAt)),
        ],
      ],
    );
  }
}

class _DoneMark extends StatelessWidget {
  const _DoneMark();

  @override
  Widget build(BuildContext context) {
    return MotionIn(
      builder: (context, t, child) =>
          Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      child: const SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.accent100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check,
            size: 30,
            color: AppColors.accent900,
            semanticLabel: '인증 완료',
          ),
        ),
      ),
    );
  }
}
