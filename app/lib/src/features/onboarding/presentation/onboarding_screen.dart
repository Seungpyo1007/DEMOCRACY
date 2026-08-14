import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:democracy/src/features/onboarding/presentation/address_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Address first, profile second, confirmation third.
///
/// The address step is the only one that gates anything. Profile is marked
/// optional by the guide and skipping it must not cost the resident anything
/// but match quality, so [_ProfileStep] has no required field and the CTA
/// stays live through it.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return PopScope(
      // Back walks the flow rather than leaving it, which is what the step
      // counter implies. Only a back press on step one exits.
      canPop: state.step == OnboardingStep.address,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          controller.back();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _StepProgress(state: state),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screen,
                  ),
                  children: [
                    const SizedBox(height: AppSpacing.x6),
                    switch (state.step) {
                      OnboardingStep.address => const _AddressStep(),
                      OnboardingStep.profile => const _ProfileStep(),
                      OnboardingStep.done => const _DoneStep(),
                    },
                    const SizedBox(height: AppSpacing.x8),
                  ],
                ),
              ),
              _BottomActions(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step counter plus bar.
///
/// The guide gives three different answers for the bar -- height 2, height 4
/// with a radius, and none at all on iOS. The README's platform split is the
/// one that reconciles them: a hairline on iOS, a rounded accent bar on
/// Android. The counter is shown on both because it is the only part that
/// says how far there is left to go.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final isGlass = surface.isGlass;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.x3,
            AppSpacing.screen,
            AppSpacing.x2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const MicroLabel('지역구 설정'),
              Text(
                '${state.stepNumber} / 3',
                style: AppTextStyles.tabLabel.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isGlass ? 0 : AppSpacing.screen,
          ),
          child: ClipRRect(
            borderRadius: isGlass
                ? BorderRadius.zero
                : BorderRadius.circular(AppRadii.androidProgress),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: isGlass ? 2 : 4,
              backgroundColor: AppColors.neutral200,
              valueColor: AlwaysStoppedAnimation(
                isGlass ? AppColors.ink : AppColors.signal,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressStep extends ConsumerWidget {
  const _AddressStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '내 지역구부터\n찾아드릴게요',
          style: surface.isGlass
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '주소는 지역구 설정과 주민 인증에만 사용되며 암호화 저장됩니다.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: AppSpacing.x6),

        _SearchField(
          query: state.query,
          onTap: () async {
            final picked = await AddressSearchSheet.show(context);
            if (picked != null) {
              controller.selectDistrict(
                picked.district,
                address: picked.address,
              );
            }
          },
        ),
        const SizedBox(height: AppSpacing.x3),

        _LocationButton(
          detecting: state.detecting,
          onPressed: controller.detectLocation,
        ),

        if (state.locationFailure != null) ...[
          const SizedBox(height: AppSpacing.x3),
          Text(
            '${state.locationFailure!.message} 주소로 직접 찾아 주세요.',
            style: AppTextStyles.disclaimer.copyWith(
              color: AppColors.neutral700,
            ),
          ),
        ],

        if (state.district != null) ...[
          const SizedBox(height: AppSpacing.x4),
          // Fades in rather than appearing, which is what the guide asks for
          // after a location lookup resolves.
          TweenAnimationBuilder<double>(
            key: ValueKey(state.district!.id),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: _DetectedDistrictCard(district: state.district!),
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final filled = query.isNotEmpty;

    return Semantics(
      button: true,
      label: '주소 검색',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(surface.cardRadius),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3 + 1,
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20, color: AppColors.neutral500),
              const SizedBox(width: AppSpacing.x2 + 2),
              Expanded(
                child: Text(
                  filled ? query : '도로명 주소 검색',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cta.copyWith(
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    color: filled ? AppColors.ink : AppColors.neutral500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({required this.detecting, required this.onPressed});

  final bool detecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final radius = BorderRadius.circular(AppRadii.androidButton);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: surface.isGlass ? surface.cardFill : AppColors.neutral200,
        borderRadius: radius,
        child: InkWell(
          onTap: detecting ? null : onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: AppSpacing.x3,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (detecting)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.my_location, size: 16, color: AppColors.ink),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  detecting ? '현재 위치 확인 중' : '현재 위치(GPS)로 자동 설정',
                  style: AppTextStyles.ctaSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectedDistrictCard extends StatelessWidget {
  const _DetectedDistrictCard({required this.district});

  final DistrictRef district;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MicroLabel('감지된 지역구'),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  district.displayName,
                  style: AppTextStyles.statValue.copyWith(
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const VerifiedBadge(label: '인증 가능'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStep extends ConsumerWidget {
  const _ProfileStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(residentProfileProvider);
    final controller = ref.read(residentProfileProvider.notifier);
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '관심사를 알려주시면\n분석이 정확해져요',
          style: surface.isGlass
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '건너뛰어도 지역구 정보와 공약은 모두 볼 수 있습니다.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: AppSpacing.x6),

        const SectionLabel('프로필 (AI 분석용 · 선택)'),
        const SizedBox(height: AppSpacing.x3),
        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            for (final tag in ResidentProfile.availableTags)
              AppFilterChip(
                label: tag,
                selected: profile.tags.contains(tag),
                onSelected: (_) => controller.toggleTag(tag),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.x6),

        const SectionLabel('정책 관심도'),
        const SizedBox(height: AppSpacing.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '분석에 반영되는 정도',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
            Text(
              profile.interestLabel,
              style: AppTextStyles.badge.copyWith(color: AppColors.ink),
            ),
          ],
        ),
        Slider(
          value: profile.interest.toDouble(),
          max: ResidentProfile.interestSteps.toDouble(),
          divisions: ResidentProfile.interestSteps,
          label: profile.interestLabel,
          activeColor: surface.isGlass ? AppColors.ink : AppColors.signal,
          inactiveColor: AppColors.neutral200,
          onChanged: (value) => controller.setInterest(value.round()),
        ),
      ],
    );
  }
}

class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final profile = ref.watch(residentProfileProvider);
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '준비가 끝났어요',
          style: surface.isGlass
              ? AppTextStyles.onboardingHeadlineIos
              : AppTextStyles.onboardingHeadlineAndroid,
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '설정한 지역구의 의원, 후보, 공약을 출처와 함께 보여드립니다.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: AppSpacing.x6),

        if (state.district != null)
          _DetectedDistrictCard(district: state.district!),
        const SizedBox(height: AppSpacing.x3),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MicroLabel('프로필'),
              const SizedBox(height: 3),
              Text(
                profile.isEmpty ? '설정하지 않음 · 나중에 바꿀 수 있습니다' : profile.summary,
                style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                '정책 관심도 ${profile.interestLabel}',
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x4),

        const DisclaimerBox(
          text: '주민 인증을 마치면 평가 작성과 이행 제보를 쓸 수 있습니다. 읽기는 인증 없이도 계속 가능합니다.',
        ),
      ],
    );
  }
}

class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.state});

  final OnboardingState state;

  /// Stands in for the residency check the BFF will run.
  ///
  /// This is the only place the app can reach `verified`, and it is a fake:
  /// the real contract issues an opaque token server-side after checking the
  /// address. Deliberately not a device biometric -- `PlatformAdaptiveAuth`
  /// exists and says in its own doc that reauthentication is not proof of
  /// residency.
  void _completeVerification(BuildContext context, WidgetRef ref) {
    final district = state.district;
    if (district == null) {
      return;
    }

    ref
        .read(addressControllerProvider.notifier)
        .acceptVerification(
          district: district,
          proof: ResidencyVerificationProof(
            opaqueToken: 'fixture-residency-token-${district.id}',
            verifiedAt: DateTime.now().toUtc(),
          ),
        );
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final isLast = state.step == OnboardingStep.done;
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x3,
        AppSpacing.screen,
        AppSpacing.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPrimaryButton(
            label: isLast ? '주민 인증 완료' : '다음',
            trailingArrow: surface.isGlass,
            onPressed: state.canAdvance
                ? () {
                    if (isLast) {
                      _completeVerification(context, ref);
                    } else {
                      controller.next();
                    }
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.x2),
          // Skipping means read-only, not district-less: every screen past
          // here is about a district, and the router sends a user without one
          // straight back. So this waits for a district too, and only the
          // verification is optional.
          TextButton(
            onPressed: state.district == null
                ? null
                : () {
                    ref
                        .read(addressControllerProvider.notifier)
                        .continueReadOnly(district: state.district);
                    context.go(AppRoutes.home);
                  },
            child: Text(
              '나중에 인증하기',
              style: AppTextStyles.cardBody.copyWith(
                color: state.district == null
                    ? AppColors.neutral400
                    : AppColors.neutral500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
