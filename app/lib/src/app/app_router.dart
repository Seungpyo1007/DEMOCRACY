import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_chrome.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_tab_page.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/history/presentation/history_screen.dart';
import 'package:democracy/src/features/onboarding/presentation/address_search_screen.dart';
import 'package:democracy/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_detail_screen.dart';
import 'package:democracy/src/features/pledges/presentation/pledge_tracker_screen.dart';
import 'package:democracy/src/features/results/presentation/election_results_screen.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:democracy/src/features/reviews/presentation/review_compose_screen.dart';
import 'package:democracy/src/features/shell/presentation/app_shell.dart';
import 'package:democracy/src/features/tutorial/presentation/tutorial_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    // Where a launch opens is decided by whether a district survived the last
    // one. The guard cannot do this on its own: it deliberately lets a
    // resident who has a district visit onboarding, because the verification
    // prompt routes here to upgrade a read-only session -- so a fixed
    // onboarding start would be allowed to stand, and a returning resident
    // would open on a screen they finished with once.
    //
    // Read, not watched: this is the location the router is built with, and
    // rebuilding a router to change it would discard the navigation stack.
    // `addressRestoreProvider` is what makes the read here meaningful, by
    // finishing before this provider is first built.
    initialLocation: ref.read(addressControllerProvider).district == null
        ? AppRoutes.onboarding
        : AppRoutes.home,
    // Onboarding is the only route reachable without a district. Without this
    // the shell was open to any deep link, and initialLocation alone stopped
    // nothing once a URL could be handed in from outside.
    redirect: (context, state) {
      final hasDistrict = ref.read(addressControllerProvider).district != null;
      final atOnboarding =
          state.matchedLocation == AppRoutes.onboarding ||
          state.matchedLocation == AppRoutes.addressSearch;

      // Only the missing-district case redirects. Sending a user who already
      // has one back out of onboarding would strand the verification prompt,
      // which deliberately routes here to upgrade a read-only session.
      return !hasDistrict && !atOnboarding ? AppRoutes.onboarding : null;
    },
    // The native tab bar and glass buttons are platform views; this tells
    // them when a sheet or dialog is up so they hide under it instead of
    // drawing through it.
    observers: [CNTabBarRouteObserver()],
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
          context: context,
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.addressSearch,
        pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
          context: context,
          key: state.pageKey,
          child: const AddressSearchScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.reviewCompose,
        pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
          context: context,
          key: state.pageKey,
          child: const ReviewComposeScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.tutorial,
        pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
          context: context,
          key: state.pageKey,
          child: TutorialScreen(
            replay: state.uri.queryParameters['replay'] == '1',
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            observers: [CNTabBarRouteObserver()],
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
            observers: [CNTabBarRouteObserver()],
            routes: [
              GoRoute(
                path: AppRoutes.history,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const HistoryScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [CNTabBarRouteObserver()],
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
            observers: [CNTabBarRouteObserver()],
            routes: [
              GoRoute(
                path: AppRoutes.aiMatch,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  // Shared with 방향 분석 below: the navigator sees one page
                  // whose content changes, not a second page pushed on top.
                  key: const ValueKey('ai-tab'),
                  child: const AiTabPage(mode: AiMode.match),
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
              // A sibling of the match, not a child: as a child it was pushed
              // over the match with a page transition and a back gesture,
              // when the switch at the top is meant to swap the view in place.
              GoRoute(
                path: AppRoutes.aiDirection,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: const ValueKey('ai-tab'),
                  child: const AiTabPage(mode: AiMode.direction),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [CNTabBarRouteObserver()],
            routes: [
              GoRoute(
                path: AppRoutes.community,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const CommunityScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [CNTabBarRouteObserver()],
            routes: [
              GoRoute(
                path: AppRoutes.results,
                pageBuilder: (context, state) => PlatformAdaptiveRoute.page(
                  context: context,
                  key: state.pageKey,
                  child: const ElectionResultsScreen(),
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
