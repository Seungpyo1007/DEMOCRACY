import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/tutorial/presentation/tutorial_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<(GoRouter, InMemoryTipStore)> pumpTutorial(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool replay = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = InMemoryTipStore();
    final router = GoRouter(
      initialLocation: replay ? AppRoutes.home : AppRoutes.tutorial,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('${AppRoutes.tutorial}?replay=1'),
              child: const Text('홈'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.tutorial,
          builder: (context, state) => TutorialScreen(
            replay: state.uri.queryParameters['replay'] == '1',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tipStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(
          theme: AppTheme.light(platform),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (replay) {
      await tester.tap(find.text('홈'));
      await tester.pumpAndSettle();
    }
    return (router, store);
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform pages through every step and ends at home', (
      tester,
    ) async {
      final (router, store) = await pumpTutorial(tester, platform: platform);

      expect(find.textContaining('당이 아닌 인물로'), findsOneWidget);
      expect(find.bySemanticsLabel('6쪽 중 1쪽'), findsOneWidget);

      for (var page = 2; page <= TutorialScreen.pageCount; page++) {
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('6쪽 중 $page쪽'), findsOneWidget);
      }

      // The last page has no skip, and its button starts the app.
      expect(find.text('건너뛰기').hitTestable(), findsNothing);
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(location(router), AppRoutes.home);
      expect(await store.load(), contains(TipIds.tutorial));
    });
  }

  testWidgets('skipping counts as seen', (tester) async {
    final (router, store) = await pumpTutorial(tester);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(location(router), AppRoutes.home);
    expect(await store.load(), contains(TipIds.tutorial));
  });

  testWidgets('pages can be swiped as well as tapped', (tester) async {
    await pumpTutorial(tester);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('6쪽 중 2쪽'), findsOneWidget);
  });

  testWidgets('a replay returns to where it was opened', (tester) async {
    final (router, _) = await pumpTutorial(tester, replay: true);
    expect(find.textContaining('당이 아닌 인물로'), findsOneWidget);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(location(router), AppRoutes.home);
  });

  testWidgets('reduced motion still pages, without the slide', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pumpTutorial(tester);
    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(find.bySemanticsLabel('6쪽 중 2쪽'), findsOneWidget);
  });
}
