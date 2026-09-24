import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The one sentence both AI views are built under (N-6, 제82조의8).
const aiDisclosure = '공약 원문 기반 참고 자료이며 공인 평가가 아닙니다.';

/// How the numbers are made, said once in the dialog so the label beside each
/// of them can stay two words long.
const aiDisclosureMethod = '점수와 위치는 등록된 공약 문구를 공개된 축과 가중치로 대조해 계산합니다.';

/// The label set beside every AI-produced score and position.
const aiReferenceLabel = 'AI 참고 자료';

/// Raised when AI-derived output is drawn with no disclosure around it.
///
/// A plain exception rather than an assert, for the same reason as
/// `MissingSourceException`: assertions are stripped from release builds, and
/// a machine-produced score presented as an assessment in production is
/// exactly the case that has to fail.
///
/// N-6 was the weakest of the six neutrality rules in practice. Provenance
/// throws when it is missing and a party colour has no field to live in, but
/// the disclosure used to be a sliver anyone could delete while the screen
/// went on compiling and the scores went on rendering.
class MissingDisclosureScopeException implements Exception {
  const MissingDisclosureScopeException({
    required this.widget,
    required this.reason,
  });

  final String widget;
  final String reason;

  @override
  String toString() => 'MissingDisclosureScopeException on $widget: $reason';
}

/// Installed by `AiTabScaffold`, required by anything that draws a score and
/// by the [AiReferenceLabel] that marks it.
///
/// The marking lives on the output itself now rather than in a band over the
/// screen: every score carries a label, and the label cannot build without
/// this scope any more than the score can. Deleting the scope deletes the
/// screen, not the notice.
class AiDisclosureScope extends InheritedWidget {
  const AiDisclosureScope({
    required this.disclosure,
    required super.child,
    super.key,
  });

  final String disclosure;

  /// Called by every widget that renders model output.
  ///
  /// It reads through [dependOnInheritedWidgetOfExactType] rather than
  /// [getInheritedWidgetOfExactType] so the lookup is registered as a
  /// dependency -- a caller cannot satisfy this and then be rebuilt somewhere
  /// the scope is gone.
  static AiDisclosureScope require(
    BuildContext context, {
    required String widget,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AiDisclosureScope>();
    if (scope == null) {
      throw MissingDisclosureScopeException(
        widget: widget,
        reason:
            'AI가 산출한 값은 고지 없이 표시할 수 없습니다. '
            'AiTabScaffold(AiDisclosureScope) 안에서 그리세요.',
      );
    }
    return scope;
  }

  @override
  bool updateShouldNotify(AiDisclosureScope oldWidget) =>
      disclosure != oldWidget.disclosure;
}

/// The full notice: what the output is, how it is made, and where to check.
///
/// Shown once on the reader's first visit to the AI tab, and again from the
/// ⓘ in the top bar or any [AiReferenceLabel]. The system's own alert, so it
/// reads as the app speaking rather than as part of the analysis.
Future<void> showAiDisclosureDialog(BuildContext context) {
  return PlatformAdaptiveDialog.show(
    context: context,
    title: 'AI 분석 안내',
    message: '$aiDisclosure\n$aiDisclosureMethod',
    secondaryLabel: '알고리즘 검증',
    onSecondary: () {
      if (context.mounted) {
        context.push(AppRoutes.algorithmLog);
      }
    },
  );
}

/// `AI 참고 자료`, set beside a score or at the head of an AI-derived section.
///
/// Quiet on purpose -- small grey type in a hairline outline, a capsule on
/// iOS and an 8dp corner on Android -- because it repeats on every figure; it
/// only has to be impossible to miss, not loud. Tapping it opens the notice.
class AiReferenceLabel extends StatelessWidget {
  const AiReferenceLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AiDisclosureScope.require(
      context,
      widget: 'AiReferenceLabel',
    );
    final isGlass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;

    return Semantics(
      button: true,
      label: '$aiReferenceLabel. ${scope.disclosure} 안내 보기',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAiDisclosureDialog(context),
        // The outline stays small; the hit area is the full 44.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: isGlass
                    ? const StadiumBorder(
                        side: BorderSide(color: AppColors.neutral400),
                      )
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.neutral400),
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2,
                  vertical: 2,
                ),
                child: Text(
                  aiReferenceLabel,
                  maxLines: 1,
                  style: AppTextStyles.badge.copyWith(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.neutral700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
