import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef VerifiedActionBuilder =
    Widget Function(BuildContext context, VoidCallback onPressed);

class VerifiedGate extends ConsumerWidget {
  const VerifiedGate({
    required this.builder,
    required this.onVerificationRequested,
    required this.onVerified,
    super.key,
  });

  final VerifiedActionBuilder builder;
  final VoidCallback onVerificationRequested;
  final VoidCallback onVerified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVerified = ref.watch(addressControllerProvider).isVerified;

    void handlePressed() {
      if (isVerified) {
        onVerified();
        return;
      }

      PlatformAdaptiveDialog.show(
        context: context,
        title: '주민 인증이 필요합니다',
        message: '읽기는 계속할 수 있지만 작성과 제보는 주소 인증 후 이용할 수 있습니다.',
        confirmLabel: '인증하러 가기',
        onConfirmed: onVerificationRequested,
      );
    }

    return builder(context, handlePressed);
  }
}
