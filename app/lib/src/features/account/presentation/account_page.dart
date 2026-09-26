import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:flutter/material.dart';

/// The page every account screen is set on: an editorial page with its own
/// title, the content as a column of rows, and the one action pinned to the
/// bottom -- floating over the page on iOS, in its own bar on Android.
///
/// The same arrangement as the review composer, so the two kinds of form in
/// the app read alike.
class AccountPage extends StatelessWidget {
  const AccountPage({
    required this.title,
    required this.children,
    this.kicker,
    this.onBack,
    this.action,
    super.key,
  });

  final String title;
  final String? kicker;
  final VoidCallback? onBack;

  /// Laid out top to bottom, each arriving after the one before.
  final List<Widget> children;

  /// The page's primary action and anything beneath it (a secondary link).
  final Widget? action;

  static const _actionClearance = 52.0 + AppSpacing.x4 * 2 + 48;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final floating = surface.isGlass && action != null;

    final page = EditorialScrollView(
      title: title,
      kicker: kicker,
      onBack: onBack,
      bottomPadding: floating ? _actionClearance : AppSpacing.x6,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.x4,
            AppSpacing.screen,
            0,
          ),
          sliver: SliverList.list(
            children: [
              for (var i = 0; i < children.length; i++)
                RevealIn(index: i, child: children[i]),
            ],
          ),
        ),
      ],
    );

    if (action == null) {
      return Scaffold(body: page);
    }

    if (floating) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: page),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: AppSpacing.x2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    0,
                    AppSpacing.x4,
                    AppSpacing.x2,
                  ),
                  child: action,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: page),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.ground,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4,
                  AppSpacing.x3,
                  AppSpacing.x4,
                  AppSpacing.x3,
                ),
                child: action,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A two-column fact row: `받는 것 | 로그인 제공자 식별자`. Used for what is
/// kept, what is discarded, what an export holds.
class FactRow extends StatelessWidget {
  const FactRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: AppTextStyles.cardBody.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lead paragraph under a page title.
class LeadText extends StatelessWidget {
  const LeadText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.cardBody.copyWith(
        color: AppColors.neutral700,
        height: 1.6,
      ),
    );
  }
}
