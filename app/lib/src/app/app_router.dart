import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:democracy/src/features/reviews/presentation/resident_review_screen.dart';
import 'package:democracy/src/features/shared/presentation/feature_placeholder_screen.dart';
import 'package:democracy/src/features/shell/presentation/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.onboarding,
    // Onboarding is the only route reachable without a district. Without this
    // the shell was open to any deep link, and initialLocation alone stopped
    // nothing once a URL could be handed in from outside.
    redirect: (context, state) {
      final hasDistrict = ref.read(addressControllerProvider).district != null;
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;

      // Only the missing-district case redirects. Sending a user who already
      // has one back out of onboarding would strand the verification prompt,
      // which deliberately routes here to upgrade a read-only session.
      return !hasDistrict && !atOnboarding ? AppRoutes.onboarding : null;
    },
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
                    notice: '공약 원문 기반 참고 자료 · 공인 평가 아님 · 알고리즘 검증 필요',
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
                  child: const ResidentReviewScreen(),
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
