import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

void main() {
  Future<ProviderContainer> pumpMatch(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        matchRepositoryProvider.overrideWithValue(
          FakeMatchRepository(
            loader: fixtureLoaderFromDisk(),
            // The stream is what is under test, not the wait.
            tokenDelay: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    final router = GoRouter(
      initialLocation: AppRoutes.aiMatch,
      routes: [
        GoRoute(
          path: AppRoutes.aiMatch,
          builder: (context, state) => const AiMatchScreen(),
          routes: [
            GoRoute(
              path: AppRoutes.algorithmLogSegment,
              builder: (context, state) => const AlgorithmLogScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(platform),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('the disclosure', () {
    // N-6 is a standing disclosure, not a splash. It has to still be on screen
    // at the moment a reader is looking at a score.
    testWidgets('stays on screen while the results scroll under it', (
      tester,
    ) async {
      await pumpMatch(tester);
      expect(find.textContaining(AiMatchScreen.disclosure), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.textContaining(AiMatchScreen.disclosure), findsOneWidget);
    });

    testWidgets('links to the weights the run actually used', (tester) async {
      await pumpMatch(tester);

      await tester.tap(find.text('오픈소스 알고리즘 검증 →'));
      await tester.pumpAndSettle();

      expect(find.text('알고리즘 검증'), findsOneWidget);
      expect(find.textContaining('axisWeights'), findsOneWidget);
      expect(find.textContaining('fixture-match-v0'), findsOneWidget);
      expect(find.text('42건'), findsOneWidget);
    });
  });

  group('the ranking', () {
    testWidgets('leads with the top match and its score', (tester) async {
      await pumpMatch(tester);

      expect(find.text('1위 매칭'), findsOneWidget);
      expect(find.text('87점'), findsOneWidget);
      expect(find.text('가상 후보 가'), findsOneWidget);
    });

    testWidgets('orders by score regardless of payload order', (tester) async {
      final container = await pumpMatch(tester);
      final report = await container.read(matchReportProvider.future);

      expect(report.matches.map((match) => match.score).toList(), [
        87.0,
        73.0,
        61.0,
      ]);
    });

    // Only the leader gets the radar and the bars; the others are a row. A
    // second full card would read as a comparison between candidates rather
    // than between each candidate and the reader.
    testWidgets('gives the runners-up a row, not a second card', (
      tester,
    ) async {
      await pumpMatch(tester);

      expect(find.text('73점'), findsOneWidget);
      expect(find.text('61점'), findsOneWidget);
      expect(find.text('2위 매칭'), findsNothing);
    });
  });

  group('the reasoning', () {
    testWidgets('arrives as a stream and lands on the full text', (
      tester,
    ) async {
      await pumpMatch(tester);

      await tester.tap(find.text('왜 유리한가'));
      await tester.pumpAndSettle();

      expect(find.textContaining('간이과세 기준 상향'), findsOneWidget);
    });

    // A model explaining itself is not evidence; the pledge text is.
    testWidgets('carries a source for every claim it makes', (tester) async {
      await pumpMatch(tester);

      await tester.tap(find.text('왜 유리한가'));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsNWidgets(2));
    });

    testWidgets('refuses a reason with no source behind it', (tester) async {
      expect(
        () => MatchReason.fromJson(const {
          'text': '근거 없는 주장입니다.',
        }, field: 'match.test.reason'),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });

  group('premium', () {
    // A button that takes money with no contract behind it would be the one
    // part of the screen promising something the app cannot deliver.
    testWidgets('is named but inert, and says so', (tester) async {
      await pumpMatch(tester);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('상세 분석 리포트 (프리미엄)'), findsOneWidget);
      expect(find.textContaining('아직 제공하지 않습니다'), findsOneWidget);
    });
  });

  group('the score', () {
    // A match score is this app's own output. Dressing it in an attribution
    // would borrow the authority the provenance rule exists to establish.
    test('is not given a source of its own', () {
      const axis = MatchAxis(label: '세금', score: 92);
      expect(axis.display, '92');
      expect(axis.fraction, closeTo(0.92, 0.001));
    });

    test('is clamped to the range it claims', () {
      expect(
        MatchAxis.fromJson(const {'label': '세금', 'score': 140}).score,
        100,
      );
      expect(MatchAxis.fromJson(const {'label': '세금', 'score': -5}).score, 0);
    });
  });

  // N-6 used to be the weakest of the six rules in practice: provenance throws
  // when it is missing and a party colour has no field to live in, but the
  // disclosure was a sliver anyone could delete while the screen went on
  // compiling. These pin the two halves of the fix.
  group('the disclosure cannot be dropped', () {
    testWidgets('a widget that draws a score refuses to build without it', (
      tester,
    ) async {
      Object? caught;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              try {
                AiDisclosureScope.require(context, widget: '_TopMatchCard');
              } on Object catch (error) {
                caught = error;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(caught, isA<MissingDisclosureScopeException>());
    });

    testWidgets('and builds happily inside one', (tester) async {
      Object? caught;

      await tester.pumpWidget(
        MaterialApp(
          home: AiDisclosureScope(
            disclosure: AiMatchScreen.disclosure,
            child: Builder(
              builder: (context) {
                try {
                  AiDisclosureScope.require(context, widget: '_TopMatchCard');
                } on Object catch (error) {
                  caught = error;
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(caught, isNull);
    });

    // The residue a type cannot express -- that the banner is still on screen
    // at the moment a reader is looking at a score -- is already pinned by
    // 'stays on screen while the results scroll under it' above.
  });
}
