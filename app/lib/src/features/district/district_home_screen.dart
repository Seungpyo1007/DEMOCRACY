import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DistrictHomeScreen extends ConsumerWidget {
  const DistrictHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(addressControllerProvider);
    final districtName = address.district?.displayName ?? '지역구 미설정';
    final statusLabel = switch (address.status) {
      AddressStatus.unverified => '읽기 전용',
      AddressStatus.pending => '인증 대기',
      AddressStatus.verified => '✓ 주민 인증됨',
    };
    final statusColor = switch (address.status) {
      AddressStatus.unverified => AppColors.neutral600,
      AddressStatus.pending => AppColors.inProgress,
      AddressStatus.verified => AppColors.fulfilled,
    };

    return Scaffold(
      appBar: const PlatformAdaptiveAppBar(title: '내 지역구'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Text(
            districtName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: Icon(Icons.verified_user_outlined, color: statusColor),
              label: Text(statusLabel),
              side: BorderSide(color: statusColor),
              backgroundColor: Colors.transparent,
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          const _FoundationCard(
            title: 'MVP 1차 세로 흐름',
            body: '의원·후보·공약·주민 평가를 Fake repository로 먼저 연결합니다.',
          ),
          const SizedBox(height: AppSpacing.x4),
          const _FoundationCard(
            title: '출처 우선 계약',
            body: '외부 수치는 원문 URL과 취득 시각을 통과한 경우에만 표시합니다.',
          ),
        ],
      ),
    );
  }
}

class _FoundationCard extends StatelessWidget {
  const _FoundationCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final surfaceTokens = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.neutral200),
        borderRadius: BorderRadius.circular(surfaceTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x2),
            Text(body),
          ],
        ),
      ),
    );
  }
}
