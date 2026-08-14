import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The address autocomplete the guide puts behind the search field.
///
/// A sheet rather than an inline list because the keyboard takes half the
/// screen on this step, and results below a field would be pushed off it.
class AddressSearchSheet extends ConsumerStatefulWidget {
  const AddressSearchSheet({super.key});

  static Future<AddressSuggestion?> show(BuildContext context) {
    return PlatformAdaptiveSheet.show<AddressSuggestion>(
      context: context,
      builder: (context) => const AddressSearchSheet(),
    );
  }

  @override
  ConsumerState<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends ConsumerState<AddressSearchSheet> {
  final _controller = TextEditingController();

  List<AddressSuggestion> _results = const [];
  bool _searching = false;

  /// Distinguishes "nothing typed yet" from "typed, and nothing matched".
  /// Both show an empty list, and only one of them is a dead end.
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);

    final results = await ref
        .read(addressSearchRepositoryProvider)
        .search(query);

    if (!mounted) {
      return;
    }
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.x4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('주소 검색'),
          const SizedBox(height: AppSpacing.x3),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '도로명 주소 검색',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '주소는 지역구 설정과 주민 인증에만 사용되며 암호화 저장됩니다.',
            style: AppTextStyles.disclaimer.copyWith(
              color: AppColors.neutral600,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Flexible(
            child: _Results(
              results: _results,
              searching: _searching,
              searched: _searched,
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.searching,
    required this.searched,
  });

  final List<AddressSuggestion> results;
  final bool searching;
  final bool searched;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
        child: Center(child: PlatformAdaptiveProgress.circular(context)),
      );
    }

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
        child: Text(
          searched
              ? '검색 결과가 없습니다. 도로명을 다시 확인해 주세요.'
              : '도로명을 입력하면 지역구를 찾아 드립니다.',
          style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (context, _) =>
          const Divider(height: 1, color: AppColors.neutral200),
      itemBuilder: (context, index) {
        final suggestion = results[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            suggestion.address,
            style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
          ),
          subtitle: Text(
            suggestion.district.displayName,
            style: AppTextStyles.statLabel.copyWith(
              color: AppColors.neutral600,
            ),
          ),
          onTap: () => Navigator.of(context).pop(suggestion),
        );
      },
    );
  }
}
