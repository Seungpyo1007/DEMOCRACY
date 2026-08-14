import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_detail_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_tracker_screen.dart';
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
                  child: const PledgeTrackerScreen(),
                ),
                routes: [
                  GoRoute(
                    path: AppRoutes.pledgeDetailSegment,
                    pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                      context: context,
                      key: state.pageKey,
                      child: PledgeDetailScreen(
                        pledgeId: state.pathParameters['id'] ?? '',
                      ),
                    ),
                  ),
                ],
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
                  child: const AiMatchScreen(),
                ),
                routes: [
                  GoRoute(
                    path: AppRoutes.algorithmLogSegment,
                    pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                      context: context,
                      key: state.pageKey,
                      child: const AlgorithmLogScreen(),
                    ),
                  ),
                ],
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
