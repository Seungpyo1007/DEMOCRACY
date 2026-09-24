import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:democracy/src/features/shell/application/tab_accessory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Reporting is a write, so it is gated like every other write.
///
/// Disabled rather than hidden: an unverified resident should be able to see
/// that reporting exists and what it would take to use it. The tracker and a
/// pledge's own page carry the same action, so it lives here once.
///
/// iOS floats a prominent Liquid Glass button above the tab bar, on the
/// [AppFloatingBar] (which draws no platter under native glass); Android uses
/// the Material 3 extended FAB at the end. Pair it with
/// [PledgeReportAction.location].
class PledgeReportAction extends StatelessWidget {
  const PledgeReportAction({super.key});

  /// The same action for the native iOS tab bar's accessory, which is not
  /// built through [VerifiedGate].
  static TabAccessory accessory(BuildContext context, WidgetRef ref) {
    return TabAccessory(
      label: '이행 제보',
      icon: AppIcons.report,
      onPressed: () => runVerified(
        context,
        ref,
        onVerificationRequested: () => context.go(AppRoutes.onboarding),
        onVerified: () => _report(context),
      ),
    );
  }

  static void _report(BuildContext context) {
    PlatformAdaptiveNotice.show(
      context,
      title: '이행 제보',
      message: '제보 화면은 다음 단계에서 연결합니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return VerifiedGate(
      onVerificationRequested: () => context.go(AppRoutes.onboarding),
      onVerified: () => _report(context),
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppPrimaryButton(
            label: '이행 제보',
            icon: AppIcons.report,
            expand: false,
            onPressed: onPressed,
          );
        }

        return AppExtendedFab(
          label: '이행 제보',
          icon: AppIcons.report.material,
          onPressed: onPressed,
        );
      },
    );
  }
}
