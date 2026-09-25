import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Address first, profile second, confirmation third.
///
/// The address step is the only one that gates anything. Profile is marked
/// optional by the guide and skipping it must not cost the resident anything
/// but match quality, so [_ProfileStep] has no required field and the CTA
/// stays live through it.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingStep _lastStep = OnboardingStep.address;

  /// Which way the last step change went, so the page slides in from the
  /// side the reader is moving towards -- forward from the right, back from
  /// the left -- and the flow feels like turning pages rather than swapping.
  bool _forward = true;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    if (state.step != _lastStep) {
      _forward = state.step.index > _lastStep.index;
      _lastStep = state.step;
    }

    final reduced = AppMotion.reduced(context);
    final current = ValueKey(state.step);

    return PopScope(
      // Back walks the flow rather than leaving it, which is what the step
      // bar implies. Only a back press on step one exits.
      canPop: state.step == OnboardingStep.address,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          controller.back();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _StepProgress(state: state),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduced ? Duration.zero : AppMotion.slow,
                  reverseDuration: reduced ? Duration.zero : AppMotion.fast,
                  switchInCurve: AppMotion.sheet,
                  switchOutCurve: AppMotion.settle,
                  layoutBuilder: (currentChild, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?currentChild],
                  ),
                  transitionBuilder: (child, animation) {
                    // Only the arriving page travels; the leaving one just
                    // fades, so the two never slide across each other.
                    final arriving = child.key == current;
                    final from = Offset(_forward ? 0.08 : -0.08, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: arriving
                          ? SlideTransition(
                              position: Tween(
                                begin: from,
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            )
                          : child,
                    );
                  },
                  child: KeyedSubtree(
                    key: current,
                    child: ListView(
                      padding: kPagePadding,
                      children: [
                        const SizedBox(height: AppSpacing.x8 + 4),
                        switch (state.step) {
                          OnboardingStep.address => const _AddressStep(),
                          OnboardingStep.profile => const _ProfileStep(),
                          OnboardingStep.done => const _DoneStep(),
                        },
                        const SizedBox(height: AppSpacing.x8),
                      ],
                    ),
                  ),
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

/// Three thin segments, one per step, filled in ink as the flow advances.
///
/// No counter text: three segments already say how far there is to go, and
/// a screen reader gets the same thing spelled out.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);

    return Semantics(
      label: '3단계 중 ${state.stepNumber}단계',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.x4,
          AppSpacing.screen,
          0,
        ),
        child: Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.x1 + 2),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: ColoredBox(
                      color: AppColors.neutral200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: i < state.stepNumber ? 1 : 0,
                        ),
                        duration: reduced ? Duration.zero : AppMotion.slow,
                        curve: AppMotion.sheet,
                        builder: (context, fill, _) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FractionallySizedBox(
                            widthFactor: fill,
                            heightFactor: 1,
                            child: const ColoredBox(color: AppColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A step's serif headline, arriving first.
class _Headline extends StatelessWidget {
  const _Headline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    return Semantics(
      header: true,
      child: Text(
        text,
        style: surface.isGlass
            ? AppTextStyles.onboardingHeadlineIos
            : AppTextStyles.onboardingHeadlineAndroid,
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.cardBody.copyWith(
        fontSize: 14,
        height: 1.55,
        color: AppColors.neutral700,
      ),
    );
  }
}

class _AddressStep extends ConsumerWidget {
  const _AddressStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MarginNote(
          '당이 아닌 인물로, 감정이 아닌 데이터로',
          fontSize: 24,
          underline: false,
        ),
        const SizedBox(height: AppSpacing.x3),
        const RevealIn(index: 1, child: _Headline('내 지역구부터\n찾아드릴게요')),
        const SizedBox(height: AppSpacing.x3),
        const RevealIn(
          index: 2,
          child: _Lead('주소는 지역구 설정과 주민 인증에만 사용되며 암호화 저장됩니다.'),
        ),
        const SizedBox(height: AppSpacing.x6 + 4),

        RevealIn(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AddressLauncher(
                query: state.query,
                onTap: () async {
                  final picked = await context.push<AddressSuggestion>(
                    AppRoutes.addressSearch,
                  );
                  if (picked != null) {
                    controller.selectDistrict(
                      picked.district,
                      address: picked.address,
                    );
                  }
                },
              ),
              const SizedBox(height: AppSpacing.x2 + 2),
              _LocationButton(
                detecting: state.detecting,
                onPressed: controller.detectLocation,
              ),
            ],
          ),
        ),

        if (state.locationFailure != null) ...[
          const SizedBox(height: AppSpacing.x3),
          RevealIn(
            key: ValueKey(state.locationFailure),
            child: Text(
              '${state.locationFailure!.message} 주소로 직접 찾아 주세요.',
              style: AppTextStyles.cardBody.copyWith(
                fontSize: 13,
                color: AppColors.neutral700,
              ),
            ),
          ),
        ],

        if (state.district != null) ...[
          const SizedBox(height: AppSpacing.x6),
          // Arrives rather than appearing, which is what the guide asks for
          // after a lookup resolves; keyed so a new district arrives again.
          RevealIn(
            key: ValueKey(state.district!.id),
            child: _DetectedDistrict(district: state.district!),
          ),
        ],
      ],
    );
  }
}

/// The door to the address search page: a ruled row with the platform's
/// magnifying glass, the chosen address once there is one, and a chevron
/// that says it opens a page rather than taking text here.
///
/// Not a search field. A field that cannot be typed into -- because tapping
/// it goes somewhere else -- was what read as wrong; a row that navigates
/// is the platform's own idiom for exactly this.
class _AddressLauncher extends StatelessWidget {
  const _AddressLauncher({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGlass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;
    final hasQuery = query.isNotEmpty;

    return Semantics(
      button: true,
      label: '주소 검색',
      value: hasQuery ? query : null,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
        ),
        child: RuledRow(
          onTap: onTap,
          minHeight: 56,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
          child: Row(
            children: [
              Icon(
                isGlass ? CupertinoIcons.search : AppIcons.search.material,
                size: 20,
                color: AppColors.ink,
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '주소 검색',
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasQuery ? query : '도로명 주소 검색',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardBody.copyWith(
                        color: hasQuery ? AppColors.ink : AppColors.neutral600,
                        fontWeight: hasQuery ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Icon(
                isGlass ? CupertinoIcons.chevron_forward : Icons.chevron_right,
                size: isGlass ? 16 : 22,
                color: AppColors.neutral600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The secondary action below the field: the platform's secondary button.
class _LocationButton extends StatelessWidget {
  const _LocationButton({required this.detecting, required this.onPressed});

  final bool detecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppSecondaryButton(
      label: detecting ? '현재 위치 확인 중' : '현재 위치로 자동 설정',
      icon: AppIcons.location,
      onPressed: detecting ? null : onPressed,
    );
  }
}

/// The district the resident is about to confirm, opened by a 2px ink rule
/// like every section in the app.
class _DetectedDistrict extends StatelessWidget {
  const _DetectedDistrict({required this.district});

  final DistrictRef district;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MicroLabel('감지된 지역구'),
            const SizedBox(height: AppSpacing.x1 + 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    district.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                const VerifiedBadge(label: '인증 가능'),
              ],
            ),
          ],
        ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RevealIn(child: _Headline('관심사를 알려주시면\n분석이 정확해져요')),
        const SizedBox(height: AppSpacing.x3),
        const RevealIn(
          index: 1,
          child: _Lead('프로필 (AI 분석용 · 선택) · 나중에 바꿀 수 있습니다'),
        ),
        const SizedBox(height: AppSpacing.x6 + 4),

        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            for (var i = 0; i < ResidentProfile.availableTags.length; i++)
              RevealIn(
                index: 2 + i,
                child: AppFilterChip(
                  label: ResidentProfile.availableTags[i],
                  selected: profile.tags.contains(
                    ResidentProfile.availableTags[i],
                  ),
                  onSelected: (_) =>
                      controller.toggleTag(ResidentProfile.availableTags[i]),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.x8),

        RevealIn(
          index: 6,
          child: _InterestScale(
            interest: profile.interest,
            label: profile.interestLabel,
            onChanged: controller.setInterest,
          ),
        ),
      ],
    );
  }
}

/// 정책 관심도: five stops, the chosen one named in the serif.
class _InterestScale extends StatelessWidget {
  const _InterestScale({
    required this.interest,
    required this.label,
    required this.onChanged,
  });

  /// The stop names printed under the track, in order.
  static const _stops = ['매우 낮음', '낮음', '보통', '높음', '매우 높음'];

  final int interest;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    '정책 관심도',
                    style: AppTextStyles.sectionLabel.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
                // The value swaps with a short fade so a drag reads as the
                // word changing, not flickering.
                AnimatedSwitcher(
                  duration: reduced ? Duration.zero : AppMotion.fast,
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: AppTextStyles.figureSmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            AppSlider(
              value: interest.toDouble(),
              max: ResidentProfile.interestSteps.toDouble(),
              divisions: ResidentProfile.interestSteps,
              valueLabel: label,
              semanticLabel: '정책 관심도',
              onChanged: (value) => onChanged(value.round()),
            ),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final stop in _stops)
                      Text(
                        stop,
                        style: AppTextStyles.disclaimer.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            const MarginNote('분석에 반영되는 정도', fontSize: 21, underline: false),
          ],
        ),
      ),
    );
  }
}

/// A calm confirmation: the district set large, what was chosen beneath it.
class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final profile = ref.watch(residentProfileProvider);
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RevealIn(child: _Headline('준비가 끝났어요')),
        const SizedBox(height: AppSpacing.x3),
        const RevealIn(
          index: 1,
          child: _Lead('설정한 지역구의 의원, 후보, 공약을 출처와 함께 보여드립니다.'),
        ),
        const SizedBox(height: AppSpacing.x8),

        if (state.district != null)
          RevealIn(
            index: 2,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MicroLabel('내 지역구'),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      state.district!.displayName,
                      style: theme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    const _UnderlinedNote('이 지역구의 기록부터 펼쳐집니다'),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.x6),

        RevealIn(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 1, color: AppColors.divider),
              _SummaryRow(
                label: '프로필',
                value: profile.isEmpty
                    ? '설정하지 않음 · 나중에 바꿀 수 있습니다'
                    : profile.summary,
              ),
              _SummaryRow(label: '정책 관심도', value: profile.interestLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x6),

        const RevealIn(
          index: 4,
          child: DisclaimerBox(
            text: '주민 인증을 마치면 평가 작성과 이행 제보를 쓸 수 있습니다. 읽기는 인증 없이도 계속 가능합니다.',
          ),
        ),
      ],
    );
  }
}

/// A margin note with its pen stroke drawn in under it.
///
/// Measured with a [TextPainter] rather than through `MarginNote`'s own
/// underline, which sizes itself with an `IntrinsicWidth` around a
/// `LayoutBuilder` and fails layout for that reason.
class _UnderlinedNote extends StatelessWidget {
  const _UnderlinedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.marginNote.copyWith(color: AppColors.signal);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();

    return RevealIn(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: style),
          HandUnderline(
            width: width,
            delay: AppMotion.staggerFor(3) + AppMotion.base,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
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
            verifiedAt: ref.read(clockProvider).now().utc,
          ),
        );
    _leave(context, ref);
  }

  /// Skipping means read-only, not district-less: every screen past here is
  /// about a district, and the router sends a user without one straight
  /// back. So this waits for a district too, and only the verification is
  /// optional.
  VoidCallback? _readOnly(BuildContext context, WidgetRef ref) {
    if (state.district == null) {
      return null;
    }
    return () {
      ref
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: state.district);
      _leave(context, ref);
    };
  }

  /// Onboarding ends at the walkthrough the first time, and at the home tab
  /// after that -- a resident returning here to verify has seen it.
  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    // Awaited: on a cold start the seen set may not have loaded yet, and an
    // unloaded set reads as "never seen" -- which sent a returning resident
    // through the walkthrough again.
    final seen = await ref.read(tipsControllerProvider.future);
    if (!context.mounted) {
      return;
    }
    context.go(
      seen.contains(TipIds.tutorial) ? AppRoutes.home : AppRoutes.tutorial,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final isLast = state.step == OnboardingStep.done;

    // The profile step's secondary action moves on without choosing; the
    // other two leave the flow read-only.
    final (secondaryLabel, secondary) = switch (state.step) {
      OnboardingStep.profile => ('건너뛰기', controller.next),
      _ => ('나중에 인증하기', _readOnly(context, ref)),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x3,
        AppSpacing.screen,
        AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.step == OnboardingStep.address) ...[
            Text(
              '건너뛰어도 지역구 정보와 공약은 모두 볼 수 있습니다.',
              textAlign: TextAlign.center,
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
          AppPrimaryButton(
            label: isLast ? '주민 인증 완료' : '다음',
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
          const SizedBox(height: AppSpacing.x1),
          _TextAction(label: secondaryLabel, onPressed: secondary),
        ],
      ),
    );
  }
}

/// A quiet way out below the primary action: Material's text button on
/// Android, a plain Cupertino button on iOS.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final style = AppTextStyles.ctaSmall.copyWith(
      color: onPressed == null ? AppColors.neutral600 : AppColors.ink,
    );

    if (surface.isGlass) {
      return CupertinoButton(
        onPressed: onPressed,
        minimumSize: const Size(44, 44),
        child: Text(label, style: style),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      child: Text(label, style: style),
    );
  }
}
