import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The walkthrough: one page per part of the app, paged through on its own
/// screen before the reader lands on the home tab.
///
/// Every illustration is built from the app's real components with sample
/// figures, so what the reader is shown here is what they will meet. The
/// copy is descriptive only (N-5): it says what a thing is and where it is,
/// never what to think of it.
///
/// Opened once after onboarding, and again from 튜토리얼 다시 보기 on the
/// home tab. [replay] decides where it ends: a first run goes on to the home
/// tab, a replay returns to where the reader was.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({this.replay = false, super.key});

  final bool replay;

  static const pageCount = 6;

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(tipsControllerProvider.notifier).dismiss(TipIds.tutorial);
    if (!mounted) {
      return;
    }
    if (widget.replay && context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _next() {
    if (_index == TutorialScreen.pageCount - 1) {
      _finish();
      return;
    }
    if (AppMotion.reduced(context)) {
      _pages.jumpToPage(_index + 1);
      return;
    }
    _pages.nextPage(
      duration: AppMotion.standard,
      curve: AppMotion.emphasizedCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;
    final last = _index == TutorialScreen.pageCount - 1;

    final skip = glass
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
            minimumSize: const Size(44, 44),
            onPressed: _finish,
            child: Text(
              '건너뛰기',
              style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
            ),
          )
        : TextButton(onPressed: _finish, child: const Text('건너뛰기'));

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Visibility(
                visible: !last,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: skip,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _index = index),
                children: const [
                  _Page(
                    kicker: 'DEMOCRACY',
                    title: '당이 아닌 인물로,\n감정이 아닌 데이터로',
                    body:
                        '내 지역구의 의원과 후보를 출처가 붙은 수치로 봅니다. '
                        '여섯 개의 탭을 차례로 소개합니다.',
                    illustration: _CoverIllustration(),
                  ),
                  _Page(
                    kicker: '01 지역구',
                    title: '모든 수치에는\n출처가 붙습니다',
                    body:
                        '수치 아래의 출처 줄을 누르면 원문이 열립니다. '
                        '오른쪽 위 버튼으로 지역구를 바꿉니다.',
                    illustration: _FiguresIllustration(),
                  ),
                  _Page(
                    kicker: '02 역사',
                    title: '한 지역구가\n걸어온 길',
                    body:
                        '지역의 연표, 역대 선거, 현직 의원의 기록을 한 곳에서 봅니다. '
                        '위의 지역 · 선거 · 의원으로 바로 이동합니다.',
                    illustration: _HistoryIllustration(),
                  ),
                  _Page(
                    kicker: '03 트래커',
                    title: '공약은\n네 가지 상태로',
                    body:
                        '이행 완료 · 진행 중 · 미이행은 먹의 진하기로, 번복만 색으로 '
                        '표시합니다. 범례를 누르면 그 상태만 모아 봅니다.',
                    illustration: _StatusIllustration(),
                  ),
                  _Page(
                    kicker: '04 AI 분석',
                    title: 'AI 분석은\n참고 자료입니다',
                    body:
                        '공약 원문을 대조한 결과이며 공인 평가가 아닙니다. '
                        '점수 옆 「AI 참고 자료」를 누르면 산출 방식과 알고리즘을 봅니다.',
                    illustration: _AiIllustration(),
                  ),
                  _Page(
                    kicker: '05 커뮤니티 · 06 개표',
                    title: '주민의 목소리와\n개표',
                    body:
                        '평가는 주소 인증을 마친 주민만 쓰며, 기본은 익명이고 게시 후 '
                        '바꿀 수 없습니다. 개표 탭은 선관위 개표 현황을 보여줍니다.',
                    illustration: _CommunityIllustration(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x2,
                AppSpacing.screen,
                AppSpacing.x4,
              ),
              child: Column(
                children: [
                  _Dots(count: TutorialScreen.pageCount, index: _index),
                  const SizedBox(height: AppSpacing.x4),
                  AppPrimaryButton(
                    label: last ? '시작하기' : '다음',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page position: the current page is a pill, the rest dots, and the pill
/// travels. Read out as "6쪽 중 N쪽".
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.standard;
    return Semantics(
      label: '$count쪽 중 ${index + 1}쪽',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: duration,
              curve: AppMotion.emphasizedCurve,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? AppColors.ink : AppColors.neutral300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.kicker,
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String kicker;
  final String title;
  final String body;
  final Widget illustration;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.x4),
          RevealIn(
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: Center(child: illustration),
            ),
          ),
          const SizedBox(height: AppSpacing.x8),
          RevealIn(
            index: 1,
            child: Text(
              kicker,
              style: AppTextStyles.sectionLabel.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          RevealIn(
            index: 2,
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTextStyles.onboardingHeadlineIos.copyWith(
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          RevealIn(
            index: 3,
            child: Text(
              body,
              style: AppTextStyles.cardBody.copyWith(
                fontSize: 16,
                height: 1.6,
                color: AppColors.neutral700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Illustrations: real components, sample figures. -----------------------

class _CoverIllustration extends StatelessWidget {
  const _CoverIllustration();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountUp(
          value: 58,
          unit: '%',
          style: AppTextStyles.figureHero.copyWith(color: AppColors.ink),
          unitStyle: AppTextStyles.figureUnit.copyWith(
            fontSize: 40,
            color: AppColors.ink,
          ),
        ),
        const MarginNote('출처가 붙은 수치만 보여줍니다'),
      ],
    );
  }
}

class _FiguresIllustration extends StatelessWidget {
  const _FiguresIllustration();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(number: '01', label: '현직 의원'),
        SizedBox(height: AppSpacing.x3),
        FigureRow(
          children: [
            FigureStat(value: 92, unit: '%', label: '출석률'),
            FigureStat(value: 31, unit: '건', label: '발의 법안'),
            FigureStat(value: 58, unit: '%', label: '공약 이행'),
          ],
        ),
        SizedBox(height: AppSpacing.x2),
        SourceLine('출처 열린국회정보 · 7월 30일 기준 ↗'),
      ],
    );
  }
}

class _HistoryIllustration extends StatelessWidget {
  const _HistoryIllustration();

  @override
  Widget build(BuildContext context) {
    const years = ['2016', '2020', '2024'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '02', label: '선거의 역사'),
        const SizedBox(height: AppSpacing.x4),
        const SizedBox(
          height: 110,
          child: DrawnLine(
            dotRadius: 4.5,
            points: [Offset(0, 0.41), Offset(0.5, 0.68), Offset(1, 0.52)],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final year in years)
              Text(
                year,
                style: AppTextStyles.figureSmall.copyWith(
                  fontSize: 15,
                  color: AppColors.neutral700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusIllustration extends StatelessWidget {
  const _StatusIllustration();

  @override
  Widget build(BuildContext context) {
    const shares = {
      PledgeStatus.fulfilled: 0.38,
      PledgeStatus.inProgress: 0.33,
      PledgeStatus.unfulfilled: 0.21,
      PledgeStatus.reversed: 0.08,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: [
              for (final (i, entry) in shares.entries.indexed)
                Expanded(
                  flex: (entry.value * 100).round(),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: GrowBar(
                      fraction: 1,
                      height: 24,
                      trackColor: Colors.transparent,
                      color: PledgeStatusChip.barColor(entry.key),
                      delay: AppMotion.staggerFor(i * 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        for (final status in shares.keys)
          RuledRow(minHeight: 40, child: PledgeStatusChip(status: status)),
      ],
    );
  }
}

class _AiIllustration extends StatelessWidget {
  const _AiIllustration();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(number: '1위', label: '매칭'),
        const SizedBox(height: AppSpacing.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '가상 후보 가',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: AppColors.ink),
              ),
            ),
            CountUp(
              value: 87,
              unit: '점',
              style: AppTextStyles.scoreDisplay.copyWith(color: AppColors.ink),
              unitStyle: AppTextStyles.figureUnit.copyWith(
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral500),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                'ⓘ AI 참고 자료',
                style: AppTextStyles.disclaimer.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        const LabeledBarsSample(),
      ],
    );
  }
}

/// Two axis bars, as the match screen draws them.
class LabeledBarsSample extends StatelessWidget {
  const LabeledBarsSample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, (label, value)) in const [
          ('세금', 92),
          ('부동산', 88),
        ].indexed) ...[
          Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  label,
                  style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
                ),
              ),
              Expanded(
                child: GrowBar(
                  fraction: value / 100,
                  delay: AppMotion.staggerFor(i + 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
      ],
    );
  }
}

class _CommunityIllustration extends StatelessWidget {
  const _CommunityIllustration();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '익명 주민',
              style: AppTextStyles.badge.copyWith(color: AppColors.ink),
            ),
            const SizedBox(width: AppSpacing.x2),
            const VerifiedBadge(label: '인증'),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '“임대주택 공약은 지켰지만 상가 공실 대책은 아직 체감이 없습니다.”',
          style: AppTextStyles.reading.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.x4),
        const MarginNote('게시 후에는 익명 여부를 바꿀 수 없음'),
      ],
    );
  }
}
