import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/interests/domain/interest_catalog.dart';
import 'package:democracy/src/features/interests/domain/interest_taxonomy.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// What the sheet hands back on 적용.
class InterestSelection {
  const InterestSelection({required this.topics, required this.context});

  final List<String> topics;
  final Set<String> context;
}

/// The interest picker, in the platform's sheet.
///
/// Edits a copy and hands it back once, on 적용, so picking three topics
/// starts one run on the device rather than three. [withContext] adds the
/// 30대·자영업·1인 가구 chips, for where the sheet is the only place to edit
/// them (the AI tab); onboarding shows those on the page itself.
Future<InterestSelection?> showInterestPicker(
  BuildContext context, {
  required ResidentProfile initial,
  bool withContext = false,
}) {
  return PlatformAdaptiveSheet.show<InterestSelection>(
    context: context,
    builder: (context) =>
        InterestPicker(initial: initial, withContext: withContext),
  );
}

/// Search over the taxonomy, or browse it by 분야; the picks so far on top.
class InterestPicker extends StatefulWidget {
  const InterestPicker({
    required this.initial,
    this.withContext = false,
    super.key,
  });

  final ResidentProfile initial;
  final bool withContext;

  @override
  State<InterestPicker> createState() => _InterestPickerState();
}

class _InterestPickerState extends State<InterestPicker> {
  late List<String> _topics = [...widget.initial.topics];
  late final Set<String> _context = {...widget.initial.context};
  final Set<String> _open = {};
  String _query = '';

  /// Set when a tap was refused for being one too many, so the limit line
  /// says why instead of the tap doing nothing.
  bool _limitHit = false;

  static const _max = ResidentProfile.maxTopics;

  void _toggle(String id) {
    setState(() {
      if (_topics.contains(id)) {
        _topics = [..._topics]..remove(id);
        _limitHit = false;
      } else if (_topics.length >= _max) {
        _limitHit = true;
      } else {
        _topics = InterestCatalog.normalise([..._topics, id]);
        _limitHit = false;
      }
    });
    PlatformAdaptiveHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final picked = [for (final id in _topics) ?InterestCatalog.find(id)];

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.86 - media.viewInsets.bottom,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x4,
                AppSpacing.screen,
                0,
              ),
              child: _Header(
                picked: picked,
                limitHit: _limitHit,
                onRemove: _toggle,
                onQuery: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Expanded(
              child: _query.trim().isEmpty
                  ? _browse(context)
                  : _Results(
                      query: _query,
                      picked: _topics.toSet(),
                      onToggle: _toggle,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x3,
                AppSpacing.screen,
                AppSpacing.x4,
              ),
              child: AppPrimaryButton(
                label: '적용',
                onPressed: () => Navigator.of(
                  context,
                ).pop(InterestSelection(topics: _topics, context: _context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _browse(BuildContext context) {
    final picked = _topics.toSet();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text(
          '고른 관심사마다 현 의원의 공약·법안과 얼마나 관련 있는지를 이 기기에서 '
          '계산합니다. 고른 내용은 이 기기에만 저장하고 어디에도 보내지 않습니다.',
          style: AppTextStyles.cardBody.copyWith(
            color: AppColors.neutral700,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        const SourceLine(
          '최대 ${ResidentProfile.maxTopics}개 · 이 기기의 AI가 한 번에 견줘 볼 수 '
          '있는 만큼입니다. 초성(ㄱㅌ)이나 비슷한 말(전세, GTX)로도 찾을 수 있습니다.',
        ),
        const SizedBox(height: AppSpacing.x6),
        if (widget.withContext) ...[
          const SectionHeader(label: '나에 대해 · 참고로만 씀'),
          const SizedBox(height: AppSpacing.x3),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (final tag in ResidentProfile.contextTags)
                AppFilterChip(
                  label: tag,
                  selected: _context.contains(tag),
                  onSelected: (_) => setState(
                    () => _context.contains(tag)
                        ? _context.remove(tag)
                        : _context.add(tag),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
        ],
        SectionHeader(
          label: '분야별로 보기',
          trailing: Text(
            '${interestAreas.length}개 분야',
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral700,
            ),
          ),
        ),
        for (final area in interestAreas)
          _AreaSection(
            area: area,
            open: _open.contains(area.id),
            picked: picked,
            onOpen: () => setState(
              () => _open.contains(area.id)
                  ? _open.remove(area.id)
                  : _open.add(area.id),
            ),
            onToggle: _toggle,
          ),
        const SizedBox(height: AppSpacing.x4),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.picked,
    required this.limitHit,
    required this.onRemove,
    required this.onQuery,
  });

  final List<Interest> picked;
  final bool limitHit;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    const max = ResidentProfile.maxTopics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '관심사',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Semantics(
              label: '$max개 중 ${picked.length}개 고름',
              excludeSemantics: true,
              child: Text(
                '${picked.length}/$max',
                style: AppTextStyles.figureSmall.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        AppSearchField(
          placeholder: '관심사 검색 (예: 지하철, 전세, ㄱㅌ)',
          onChanged: onQuery,
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x3),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (final interest in picked)
                AppInputChip(
                  label: interest.label,
                  caption: interest.isWholeArea ? '전체' : interest.area.label,
                  onRemove: () => onRemove(interest.id),
                ),
            ],
          ),
        ],
        // Pinned here, by the chips, only when a tap was refused: the
        // standing explanation of the limit scrolls with the list.
        if (limitHit) ...[
          const SizedBox(height: AppSpacing.x2),
          Text(
            '$max개까지 고를 수 있습니다. 하나를 빼고 다시 고르세요.',
            style: AppTextStyles.disclaimer.copyWith(
              color: AppColors.systemError,
            ),
          ),
        ],
      ],
    );
  }
}

/// One 분야: a row that opens to its topics, with the whole 분야 first.
class _AreaSection extends StatelessWidget {
  const _AreaSection({
    required this.area,
    required this.open,
    required this.picked,
    required this.onOpen,
    required this.onToggle,
  });

  final InterestArea area;
  final bool open;
  final Set<String> picked;
  final VoidCallback onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final isGlass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;
    final whole = InterestCatalog.wholeArea(area);
    final topics = InterestCatalog.topicsOf(area);
    final count = [whole, ...topics].where((i) => picked.contains(i.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: RuledRow(
            onTap: onOpen,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    area.label,
                    style: AppTextStyles.cardBody.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.x2),
                    child: Text(
                      '$count개 고름',
                      style: AppTextStyles.statLabel.copyWith(
                        color: AppColors.signal,
                      ),
                    ),
                  ),
                Text(
                  '${topics.length}',
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Icon(
                  switch ((isGlass, open)) {
                    (true, true) => CupertinoIcons.chevron_up,
                    (true, false) => CupertinoIcons.chevron_down,
                    (false, true) => Icons.expand_less,
                    (false, false) => Icons.expand_more,
                  },
                  size: isGlass ? 16 : 22,
                  color: AppColors.neutral600,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
            child: Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x2,
              children: [
                AppFilterChip(
                  label: '${area.label} 전체',
                  selected: picked.contains(whole.id),
                  onSelected: (_) => onToggle(whole.id),
                ),
                for (final topic in topics)
                  AppFilterChip(
                    label: topic.label,
                    selected: picked.contains(topic.id),
                    onSelected: (_) => onToggle(topic.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Search results: each topic with its 분야 under it.
class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.picked,
    required this.onToggle,
  });

  final String query;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final results = searchInterests(query);

    if (results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          const SizedBox(height: AppSpacing.x3),
          Text(
            '‘${query.trim()}’에 맞는 관심사가 없습니다.',
            style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.x1),
          const SourceLine('초성(ㄱㅌ)이나 비슷한 말(전세, GTX)로도 찾을 수 있습니다.'),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final interest = results[i];
        final selected = picked.contains(interest.id);
        return Semantics(
          button: true,
          selected: selected,
          child: RuledRow(
            onTap: () => onToggle(interest.id),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        interest.label,
                        style: AppTextStyles.cardBody.copyWith(
                          color: AppColors.ink,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      MicroLabel(
                        interest.isWholeArea
                            ? '분야 전체'
                            : '${interest.area.label} 분야',
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Theme.of(context).extension<AppSurfaceTokens>()!.isGlass
                        ? CupertinoIcons.checkmark_alt
                        : Icons.check,
                    size: 20,
                    color: AppColors.signal,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
