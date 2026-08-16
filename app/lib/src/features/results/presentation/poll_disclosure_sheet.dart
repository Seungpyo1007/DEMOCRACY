import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/features/results/domain/poll_disclosure.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';

/// The 제108조제5항 items in full.
///
/// It takes a [PollDisclosure] rather than loose strings, for the same reason
/// [SourceBadge] takes a [SourceMetadata]: a screen that could assemble this
/// from parts could assemble it from some of them.
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
        AppSpacing.x2,
        AppSpacing.screen,
        AppSpacing.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('여론조사 표기사항', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          const SectionLabel('공직선거법 제108조제5항'),
          const SizedBox(height: AppSpacing.x4),
          for (final (label, value) in rows) ...[
            _DisclosureRow(label: label, value: value),
            const SizedBox(height: AppSpacing.x3),
          ],
          const Divider(height: AppSpacing.x6, color: AppColors.neutral300),
          // The two links are the point of the article: the reader can check
          // the wording that produced the number and the registry entry that
          // says the survey exists.
          _DisclosureLink(label: '질문내용 원문', url: disclosure.questionnaire),
          const SizedBox(height: AppSpacing.x3),
          _DisclosureLink(
            label: '중앙선거여론조사심의위원회 등록현황',
            url: disclosure.nesdcRegistration,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
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
    );
  }
}

class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: 2),
        // The URL is shown rather than hidden behind the label. A reader who
        // cannot tap it can still type it, and one who can tap it can see
        // where it goes first.
        Text(
          url.toString(),
          style: AppTextStyles.cardBody.copyWith(color: AppColors.accent700),
        ),
      ],
    );
  }
}
