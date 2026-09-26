import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/results/domain/poll_disclosure.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The 제108조제5항 items in full.
///
/// It takes a [PollDisclosure] rather than loose strings, for the same reason
/// [SourceBadge] takes a [SourceMetadata]: a screen that could assemble this
/// from parts could assemble it from some of them. Every field of the
/// disclosure is drawn -- the eight items as ruled rows, the two links, and
/// the provenance of the disclosure itself.
///
/// The inline notice on the legend carries the headline items, because the law
/// asks the disclosure to accompany the result rather than to be reachable
/// from it. This is where the rest lives, including the two links a reader
/// needs to check the claim for themselves.
abstract final class PollDisclosureSheet {
  static Future<void> show(BuildContext context, PollDisclosure disclosure) {
    return PlatformAdaptiveSheet.show<void>(
      context: context,
      builder: (context) => _PollDisclosureBody(disclosure: disclosure),
    );
  }
}

class _PollDisclosureBody extends StatelessWidget {
  const _PollDisclosureBody({required this.disclosure});

  final PollDisclosure disclosure;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('조사기관', disclosure.pollster),
      ('조사의뢰자', disclosure.client),
      (
        '조사일시',
        '${disclosure.fieldStart.dayLabel} ~ ${disclosure.fieldEnd.dayLabel}',
      ),
      ('표본크기', '${disclosure.sampleSize}명'),
      ('피조사자 선정방법', disclosure.samplingMethod),
      ('조사방법', disclosure.surveyMethod),
      (
        '표본오차',
        '±${disclosure.marginOfError.toStringAsFixed(1)}%p '
            '(신뢰수준 ${disclosure.confidenceLevel.round()}%)',
      ),
      ('응답률', '${disclosure.responseRate.toStringAsFixed(1)}%'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.x3 + 2,
        AppSpacing.screen,
        AppSpacing.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '공직선거법 제108조제5항',
            style: AppTextStyles.sectionLabel.copyWith(color: AppColors.signal),
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          Semantics(
            header: true,
            child: Text(
              '여론조사 표기사항',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          const Divider(height: 2, thickness: 2, color: AppColors.ink),
          for (var i = 0; i < rows.length; i++)
            RevealIn(
              index: i,
              child: _DisclosureRow(label: rows[i].$1, value: rows[i].$2),
            ),
          // The two links are the point of the article: the reader can check
          // the wording that produced the number and the registry entry that
          // says the survey exists.
          RevealIn(
            index: rows.length,
            child: _DisclosureLink(
              label: '질문내용 원문',
              url: disclosure.questionnaire,
            ),
          ),
          RevealIn(
            index: rows.length + 1,
            child: _DisclosureLink(
              label: '중앙선거여론조사심의위원회 등록현황',
              url: disclosure.nesdcRegistration,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          SourceBadge(source: disclosure.source),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '앱 내 조사는 공인 조사가 아닙니다. 표본과 방법이 공개된 공인 조사와 같은 무게로 읽지 마세요.',
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 116,
              child: Text(
                label,
                style: AppTextStyles.statLabel.copyWith(
                  color: AppColors.neutral600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2 + 2),
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.ctaSmall.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two links, as the platform's own text button.
///
/// The button is a real `TextButton` on Android and a `CupertinoButton` on
/// iOS, led by the "opens elsewhere" glyph ([AppIcons.source]) so the reader
/// knows before tapping that it leaves the app.
class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({required this.label, required this.url});

  final String label;
  final Uri url;

  void _open() => launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;
    final text = AppTextStyles.ctaSmall.copyWith(color: AppColors.ink);

    final button = glass
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: _open,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The SF Symbol named by AppIcons.source, as Cupertino draws
                // it where UIKit is not embedded.
                const Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 18,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppSpacing.x2),
                Flexible(child: Text(label, style: text)),
              ],
            ),
          )
        : TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ink,
              minimumSize: const Size(44, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
              alignment: AlignmentDirectional.centerStart,
            ),
            onPressed: _open,
            icon: Icon(AppIcons.source.material, size: 18),
            label: Text(label, style: text),
          );

    return Semantics(
      link: true,
      label: '$label, $url',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.x1,
            bottom: AppSpacing.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: AlignmentDirectional.centerStart, child: button),
              // The URL is shown rather than hidden behind the label. A
              // reader who cannot tap it can still type it, and one who can
              // tap it can see where it goes first.
              Text(
                url.toString(),
                style: AppTextStyles.disclaimer.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
