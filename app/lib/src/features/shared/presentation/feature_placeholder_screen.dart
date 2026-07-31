import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FeaturePlaceholderScreen extends StatelessWidget {
  const FeaturePlaceholderScreen({
    required this.title,
    required this.description,
    this.notice,
    this.protectedActionLabel,
    super.key,
  });

  final String title;
  final String description;
  final String? notice;
  final String? protectedActionLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PlatformAdaptiveAppBar(title: title),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          if (notice != null) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.neutral400),
                color: AppColors.neutral100,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x3),
                child: Text('ⓘ ${notice!}'),
              ),
            ),
            const SizedBox(height: AppSpacing.x6),
          ],
          Text('구조만 연결된 화면', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.x3),
          Text(description),
          const SizedBox(height: AppSpacing.x6),
          if (protectedActionLabel != null)
            VerifiedGate(
              onVerificationRequested: () => context.go(AppRoutes.onboarding),
              onVerified: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('인증된 작성 흐름 연결 지점')),
                );
              },
              builder: (context, onPressed) => FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.edit_outlined),
                label: Text(protectedActionLabel!),
              ),
            ),
        ],
      ),
    );
  }
}
