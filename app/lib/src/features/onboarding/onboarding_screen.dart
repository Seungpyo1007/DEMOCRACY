import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const _previewDistrict = DistrictRef(
    id: 'fixture-seoul-mapo-b',
    displayName: '서울 마포구 을',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surfaceTokens = Theme.of(context).extension<AppSurfaceTokens>()!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const LinearProgressIndicator(value: 1 / 3, minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screen),
                children: [
                  const SizedBox(height: AppSpacing.x8),
                  Text(
                    '주소 인증 및\n지역구 설정',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    '원주소는 장기 보관하지 않고, 실제 서비스에서는 서버가 발급한 검증 토큰만 저장합니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.x8),
                  const TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '주소 검색',
                      hintText: '도로명 또는 현재 위치',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.neutral400),
                      borderRadius: BorderRadius.circular(
                        surfaceTokens.cardRadius,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.x4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _previewDistrict.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Text(
                            '✓ 인증 가능',
                            style: TextStyle(
                              color: AppColors.fulfilled,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Text(
                    '현재 화면은 구조 검증용입니다. 실제 주소 검색, GPS, 프로필 단계는 MVP 1차에서 연결합니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.x3,
                AppSpacing.screen,
                AppSpacing.x4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(addressControllerProvider.notifier)
                          .requestVerification(district: _previewDistrict);
                      context.go(AppRoutes.home);
                    },
                    child: const Text('지역구 설정 완료'),
                  ),
                  TextButton(
                    onPressed: () {
                      ref
                          .read(addressControllerProvider.notifier)
                          .continueReadOnly(district: _previewDistrict);
                      context.go(AppRoutes.home);
                    },
                    child: const Text('나중에 인증하기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
