import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Address search, full screen. Pops with the chosen [AddressSuggestion].
///
/// A page of its own rather than a sheet: the keyboard takes half the screen
/// while typing, and a sheet under it left the results a sliver to scroll.
/// Here the field sits at the top where the platform puts search -- iOS's
/// search field beside a glass back button, Android's Material 3 search bar
/// with the back arrow as its leading icon -- and the results fill the rest.
///
/// A device location resolves to a district, not an address, so that row
/// pops with [currentLocationLabel] standing in for the address.
class AddressSearchScreen extends ConsumerStatefulWidget {
  const AddressSearchScreen({super.key});

  /// The address shown for a district found from the device's location.
  static const currentLocationLabel = '현재 위치';

  @override
  ConsumerState<AddressSearchScreen> createState() =>
      _AddressSearchScreenState();
}

class _AddressSearchScreenState extends ConsumerState<AddressSearchScreen> {
  final _controller = TextEditingController();

  List<AddressSuggestion> _results = const [];
  bool _searching = false;

  /// Distinguishes "nothing typed yet" from "typed, and nothing matched".
  /// Both show an empty list, and only one of them is a dead end.
  bool _searched = false;

  /// Bumped per query so a slow answer to an older one cannot overwrite the
  /// results for what is in the field now.
  int _generation = 0;

  bool _detecting = false;
  LocationFailure? _locationFailure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await ref
        .read(addressSearchRepositoryProvider)
        .search(query);

    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _detectLocation() async {
    setState(() {
      _detecting = true;
      _locationFailure = null;
    });

    final result = await ref.read(locationRepositoryProvider).detectDistrict();
    if (!mounted) {
      return;
    }

    switch (result) {
      case LocationResolved(:final district):
        setState(() => _detecting = false);
        _pick(
          AddressSuggestion(
            address: AddressSearchScreen.currentLocationLabel,
            district: district,
          ),
        );
      case LocationRejected(:final failure):
        setState(() {
          _detecting = false;
          _locationFailure = failure;
        });
    }
  }

  void _pick(AddressSuggestion suggestion) => context.pop(suggestion);

  @override
  Widget build(BuildContext context) {
    final isGlass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isGlass ? AppSpacing.screen - 4 : AppSpacing.x4,
                AppSpacing.x2,
                isGlass ? AppSpacing.screen : AppSpacing.x4,
                AppSpacing.x2,
              ),
              child: isGlass
                  ? _IosSearchTop(controller: _controller, onChanged: _search)
                  : _AndroidSearchTop(
                      controller: _controller,
                      onChanged: _search,
                    ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.x2,
                  AppSpacing.screen,
                  MediaQuery.paddingOf(context).bottom + AppSpacing.x6,
                ),
                children: [
                  // The guidance and the location button are there on the
                  // first frame, with the search field: they are how the
                  // page is used, not content to be revealed. Only results
                  // arrive in order.
                  const _Helper(),
                  const SizedBox(height: AppSpacing.x4),
                  const Divider(height: 1, color: AppColors.divider),
                  _LocationRow(
                    detecting: _detecting,
                    onTap: _detecting ? null : _detectLocation,
                  ),
                  if (_locationFailure != null)
                    RevealIn(
                      key: ValueKey(_locationFailure),
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.x3),
                        child: Text(
                          '${_locationFailure!.message} 주소로 직접 찾아 주세요.',
                          style: AppTextStyles.cardBody.copyWith(
                            fontSize: 13,
                            color: AppColors.neutral700,
                          ),
                        ),
                      ),
                    ),
                  ..._resultsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultsSection() {
    if (_searching) {
      return [const InkLoadingSection()];
    }

    if (_results.isEmpty) {
      if (!_searched) {
        return const [];
      }
      return [
        RevealIn(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
            child: Text(
              '검색 결과가 없습니다. 도로명을 다시 확인해 주세요.',
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
        ),
      ];
    }

    // Hairlines between results rather than tiles: the page is part of the
    // same printed record as every other screen.
    return [
      for (var i = 0; i < _results.length; i++)
        RevealIn(
          // Keyed by the address so a fresh set of results arrives again
          // rather than silently swapping text under the reader.
          key: ValueKey('${_generation}_${_results[i].address}'),
          index: i,
          child: _ResultRow(
            suggestion: _results[i],
            onTap: () => _pick(_results[i]),
          ),
        ),
    ];
  }
}

/// iOS: a glass back button beside the system search field, as Settings and
/// Maps set a pushed search.
class _IosSearchTop extends StatelessWidget {
  const _IosSearchTop({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppToolbarButton(
          icon: AppIcons.back,
          label: '뒤로',
          onPressed: () => context.pop(),
        ),
        const SizedBox(width: AppSpacing.x2 + 2),
        Expanded(
          child: AppSearchField(
            placeholder: '도로명 주소 검색',
            controller: controller,
            autofocus: true,
            onChanged: onChanged,
            onSubmitted: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Android: Material 3's full-screen search pattern -- the search bar at the
/// top with the back arrow as its leading icon and a clear action once there
/// is text.
class _AndroidSearchTop extends StatelessWidget {
  const _AndroidSearchTop({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: controller,
      hintText: '도로명 주소 검색',
      autoFocus: true,
      elevation: const WidgetStatePropertyAll(0),
      onChanged: onChanged,
      onSubmitted: onChanged,
      leading: IconButton(
        tooltip: '뒤로',
        icon: Icon(AppIcons.back.material),
        onPressed: () => context.pop(),
      ),
      trailing: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ],
    );
  }
}

class _Helper extends StatelessWidget {
  const _Helper();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '도로명을 입력하면 지역구를 찾아 드립니다.',
          style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          '주소는 지역구 설정과 주민 인증에만 사용되며 암호화 저장됩니다.',
          style: AppTextStyles.disclaimer.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }
}

/// The first row of the list: the device's location, for a reader who would
/// rather not type.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.detecting, required this.onTap});

  final bool detecting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = detecting ? '현재 위치 확인 중' : '현재 위치로 찾기';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: RuledRow(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: detecting
                  ? const Center(child: InkRingIndicator())
                  : Icon(
                      AppIcons.location.material,
                      size: 20,
                      color: AppColors.ink,
                    ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.suggestion, required this.onTap});

  final AddressSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RuledRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2 + 2),
      child: Row(
        children: [
          const SizedBox(width: 24),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.address,
                  style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.district.displayName,
                  style: AppTextStyles.statLabel.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
