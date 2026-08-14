import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/shell/presentation/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The shell's two scroll behaviours, neither of which the feature screens can
/// demonstrate yet: every screen is currently shorter than the viewport, so
/// nothing scrolls and nothing proves that a branch keeps its offset.
///
/// These use their own tall branches rather than the real ones so the checks
/// stay about the shell. Wiring them to DistrictHomeScreen would make them fail
/// the day that screen's content changes height, which is not what is under
/// test here.
void main() {
  const branchPrefixes = ['A', 'B', 'C', 'D', 'E'];
  const rowsPerBranch = 40;

  Widget branchList(String prefix) {
    return Scaffold(
      body: ListView.builder(
        key: ValueKey('list-$prefix'),
        itemCount: rowsPerBranch,
        itemBuilder: (context, index) =>
            SizedBox(height: 80, child: Center(child: Text('$prefix$index'))),
      ),
    );
  }

  /// A branch with nothing scrollable, standing in for the tracker, AI and
  /// election placeholders.
  Widget staticBranch(String prefix) {
    return Scaffold(body: Center(child: Text('${prefix}static')));
  }

  GoRouter buildRouter({Set<int> staticBranches = const {}}) {
    return GoRouter(
      initialLocation: '/b0',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            for (var i = 0; i < branchPrefixes.length; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/b$i',
                    builder: (context, state) => staticBranches.contains(i)
                        ? staticBranch(branchPrefixes[i])
                        : branchList(branchPrefixes[i]),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpShell(
    WidgetTester tester,
    TargetPlatform platform, {
    Set<int> staticBranches = const {},
  }) async {
    final router = buildRouter(staticBranches: staticBranches);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(platform), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapDestination(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  // `docs/INITIAL_PLAN.md` requires "5탭 전환과 각 탭 상태 보존". Switching was
  // already covered; the preserved half was not, because no screen was tall
  // enough to have an offset worth preserving.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform keeps each branch scrolled where the user left it', (
      tester,
    ) async {
      await pumpShell(tester, platform);

      expect(find.text('A0'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('list-A')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(find.text('A0'), findsNothing);

      // Second branch, scrolled to a different offset so a shared position
      // would show up as one of them landing on the other's row.
      await tapDestination(tester, Icons.donut_large_outlined);
      expect(find.text('B0'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('list-B')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      await tapDestination(tester, Icons.location_on_outlined);
      expect(
        find.text('A0'),
        findsNothing,
        reason: 'returning to a branch must not reset it to the top',
      );

      await tapDestination(tester, Icons.donut_large_outlined);
      expect(find.text('B0'), findsNothing);
      expect(find.text('B4'), findsOneWidget);
    });
  }

  group('the bar reacts to sustained travel, not to jitter', () {
    // _AppShellState._threshold is 28: less than that in one direction is
    // treated as jitter, which is what a released drag emits.
    testWidgets('a short drag leaves the bar expanded', (tester) async {
      await pumpShell(tester, TargetPlatform.iOS);

      await tester.drag(
        find.byKey(const ValueKey('list-A')),
        const Offset(0, -20),
      );
      await tester.pumpAndSettle();

      expect(find.text('지역구'), findsOneWidget);
    });

    testWidgets('a sustained drag down contracts it', (tester) async {
      await pumpShell(tester, TargetPlatform.iOS);
      expect(find.text('지역구'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('list-A')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('지역구'), findsNothing);
    });

    testWidgets('coming back to the top restores it', (tester) async {
      await pumpShell(tester, TargetPlatform.iOS);

      await tester.drag(
        find.byKey(const ValueKey('list-A')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text('지역구'), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('list-A')),
        const Offset(0, 900),
      );
      await tester.pumpAndSettle();

      expect(find.text('지역구'), findsOneWidget);
    });
  });

  // This test used to pin the opposite. The contracted bar followed the reader
  // into the next tab and stayed contracted, because the only thing that
  // reopens it is a scroll to the top and arriving at a branch is not a
  // scroll. It was recorded as the behaviour that existed while reopening was
  // still a product question; it is not a question -- a bar contracted over
  // content the reader has not scrolled is lying about where they are.
  testWidgets('reopens when the reader changes tab', (tester) async {
    await pumpShell(tester, TargetPlatform.iOS, staticBranches: {1});

    await tester.drag(
      find.byKey(const ValueKey('list-A')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('지역구'), findsNothing);

    await tapDestination(tester, Icons.donut_large_outlined);

    expect(find.text('Bstatic'), findsOneWidget);
    expect(
      find.text('지역구'),
      findsOneWidget,
      reason: 'a branch nobody has scrolled must not look scrolled',
    );
  });

  // Coming back is the same question in reverse: the branch kept its offset,
  // so the bar should not claim the reader is at the top of it.
  testWidgets('a scrolled branch does not pretend to be at the top', (
    tester,
  ) async {
    await pumpShell(tester, TargetPlatform.iOS);

    await tester.drag(
      find.byKey(const ValueKey('list-A')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    await tapDestination(tester, Icons.donut_large_outlined);
    expect(find.text('지역구'), findsOneWidget);

    await tapDestination(tester, Icons.location_on_outlined);
    await tester.drag(
      find.byKey(const ValueKey('list-A')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();

    expect(find.text('지역구'), findsNothing);
  });
}
