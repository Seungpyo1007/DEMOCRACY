import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/features/district/district_home_screen.dart';
import 'package:democracy/src/features/onboarding/onboarding_screen.dart';
import 'package:democracy/src/features/shared/feature_placeholder_screen.dart';
import 'package:democracy/src/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
          context: context,
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const DistrictHomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tracker,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const FeaturePlaceholderScreen(
                    title: '공약 트래커',
                    description: '공약 분포와 판정 타임라인은 MVP 2차에서 구현합니다.',
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.aiMatch,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const FeaturePlaceholderScreen(
                    title: 'AI 분석',
                    description: '공약 원문과 공개된 가중치 계약 확정 후 구현합니다.',
                    notice:
                        '공약 원문 기반 참고 자료 · 공인 평가 아님 · 알고리즘 검증 필요',
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.community,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const FeaturePlaceholderScreen(
                    title: '주민 평가',
                    description: '평가 읽기와 인증된 작성 흐름을 MVP 1차에서 연결합니다.',
                    protectedActionLabel: '평가 작성하기',
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.results,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const FeaturePlaceholderScreen(
                    title: '개표',
                    description: 'GeoJSON, SSE와 폴링 계약 확정 후 구현합니다.',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
