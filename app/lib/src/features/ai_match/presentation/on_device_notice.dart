import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_providers.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The headline for a device that cannot run the model.
const onDeviceUnavailableTitle = '이 기기에서는 온디바이스 AI를 쓸 수 없습니다';

/// Why there is no AI output here, said plainly.
///
/// This is the whole of what an unsupported device sees in place of a score:
/// the headline, the reason (지원 기기 아님, Apple Intelligence 꺼짐, 모델
/// 준비 중 …) and what to do about it. No sample figure is drawn under it --
/// on a device that cannot run the model there is nothing true to show.
class OnDeviceUnavailableNotice extends ConsumerWidget {
  const OnDeviceUnavailableNotice({
    required this.reason,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final ModelUnavailableReason reason;

  /// Offered for a reason that can change while the app is open.
  final VoidCallback? onRetry;

  /// Inside a section rather than filling the page: no headline rule.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = AppTextStyles.cardBody.copyWith(
      color: AppColors.neutral700,
      height: 1.55,
    );
    final canRetry =
        onRetry != null &&
        (reason == ModelUnavailableReason.modelNotReady ||
            reason == ModelUnavailableReason.modelDownloadable ||
            reason == ModelUnavailableReason.appleIntelligenceNotEnabled);

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            onDeviceUnavailableTitle,
            style:
                (compact
                        ? AppTextStyles.cardBody.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: reason.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                TextSpan(text: ' · ${reason.detail}'),
              ],
            ),
            style: body,
          ),
          if (!compact) ...[
            const SizedBox(height: AppSpacing.x2),
            const SourceLine('AI 분석은 이 기기의 모델로만 하며, 서버의 모델로 대신하지 않습니다.'),
          ],
          if (reason == ModelUnavailableReason.modelDownloadable) ...[
            const SizedBox(height: AppSpacing.x3),
            AppSecondaryButton(
              label: '모델 내려받기',
              expand: false,
              onPressed: () async {
                await ref.read(onDeviceModelProvider).prepare();
                onRetry?.call();
              },
            ),
          ] else if (canRetry) ...[
            const SizedBox(height: AppSpacing.x3),
            AppSecondaryButton(
              label: '다시 확인',
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// 「이 기기에서 생성 · 9월 30일」, set under every on-device result.
class OnDeviceStamp extends StatelessWidget {
  const OnDeviceStamp({required this.run, super.key});

  final OnDeviceRun run;

  @override
  Widget build(BuildContext context) {
    return SourceLine(
      '$onDeviceLabel · ${KstInstant.fromDateTime(run.generatedAt).dayLabel}',
    );
  }
}
