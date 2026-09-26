import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/fake_direction_repository.dart';
import 'package:democracy/src/features/ai_match/data/fake_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_direction_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/cupertino.dart';
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
    TipStore? tips,
    bool onScreen = true,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        // Unset, the default store reports every tip seen and no dialog
        // appears; the first-visit tests pass their own.
        if (tips != null) tipStoreProvider.overrideWithValue(tips),
        matchRepositoryProvider.overrideWithValue(
          FakeMatchRepository(
            loader: fixtureLoaderFromDisk(),
            // The stream is what is under test, not the wait.
            tokenDelay: Duration.zero,
          ),
        ),
        directionRepositoryProvider.overrideWithValue(
          FakeDirectionRepository(loader: fixtureLoaderFromDisk()),
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
            GoRoute(
              path: AppRoutes.aiDirectionSegment,
              builder: (context, state) => const AiDirectionScreen(),
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
          // The shell keeps an unvisited tab built but offstage, tickers off.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: TickerMode(enabled: onScreen, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // The toggle sits under the leader's bars, below the fold once the native
  // top bar and segmented control have taken their share of the screen.
  Future<void> openReasoning(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('왜 유리한가'));
    await tester.pumpAndSettle();
  }

  group('the disclosure', () {
    // N-6 is a standing disclosure, not a splash: the marking sits on the
    // output itself, so it is on screen whenever a score is.
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${platform.name}: labels every score it shows', (
        tester,
      ) async {
        await pumpMatch(tester, platform: platform);
        await tester.scrollUntilVisible(
          find.text('3위'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final scores = find.textContaining(
          RegExp(r'^\d+점$'),
          findRichText: true,
        );
        final labels = find.byType(AiReferenceLabel);
        expect(scores, findsNWidgets(3));
        expect(labels, findsNWidgets(3));
        expect(find.text(aiReferenceLabel), findsNWidgets(3));

        // Each label sits directly under its own figure.
        for (final label in ['87점', '73점', '61점']) {
          final score = tester.getRect(find.text(label, findRichText: true));
          final nearest =
              [for (var i = 0; i < 3; i++) tester.getRect(labels.at(i))]
                  .where((rect) => (rect.top - score.bottom).abs() < 16)
                  .where((rect) => (rect.right - score.right).abs() < 16);
          expect(nearest, hasLength(1), reason: label);
        }
      });
    }

    // iOS, where no app bar brings a persistent header of its own.
    testWidgets('no longer pins a band over the results', (tester) async {
      await pumpMatch(tester, platform: TargetPlatform.iOS);

      expect(find.byType(SliverPersistentHeader), findsNothing);
      expect(find.text(aiDisclosure), findsNothing);
    });

    testWidgets('a label opens the notice', (tester) async {
      await pumpMatch(tester);

      await tester.tap(find.byType(AiReferenceLabel).first);
      await tester.pumpAndSettle();

      expect(find.text('AI 분석 안내'), findsOneWidget);
      expect(find.textContaining(aiDisclosure), findsOneWidget);
      expect(find.textContaining(aiDisclosureMethod), findsOneWidget);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${platform.name}: the ⓘ reopens the notice natively', (
        tester,
      ) async {
        await pumpMatch(tester, platform: platform);

        await tester.tap(_action(platform, 'AI 분석 안내'));
        await tester.pumpAndSettle();

        expect(
          find.byType(
            platform == TargetPlatform.iOS ? CupertinoAlertDialog : AlertDialog,
          ),
          findsOneWidget,
        );
        expect(find.textContaining(aiDisclosure), findsOneWidget);

        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();
        expect(find.textContaining(aiDisclosure), findsNothing);
      });
    }

    testWidgets('links to the weights the run actually used', (tester) async {
      await pumpMatch(tester);

      await tester.tap(_action(TargetPlatform.android, 'AI 분석 안내'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('알고리즘 검증'));
      await tester.pumpAndSettle();

      expect(find.text('알고리즘 검증'), findsOneWidget);
      expect(find.textContaining('axisWeights'), findsOneWidget);
      expect(find.textContaining('fixture-match-v0'), findsOneWidget);
      expect(find.text('42건'), findsOneWidget);
    });

    testWidgets('keeps the labels whole at a larger text size', (tester) async {
      await pumpMatch(tester, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.byType(AiReferenceLabel), findsWidgets);
    });
  });

  group('the first visit', () {
    testWidgets('opens the notice once, and remembers it was read', (
      tester,
    ) async {
      final tips = InMemoryTipStore();
      await pumpMatch(tester, tips: tips);

      expect(find.text('AI 분석 안내'), findsOneWidget);
      expect(find.textContaining(aiDisclosure), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.textContaining(aiDisclosure), findsNothing);
      expect(await tips.load(), contains(TipIds.aiDisclosure));

      // Back to the tab in a later session: no dialog.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpMatch(tester, tips: tips);
      expect(find.textContaining(aiDisclosure), findsNothing);
    });

    testWidgets('stays closed on switching views after it was read', (
      tester,
    ) async {
      await pumpMatch(tester, tips: InMemoryTipStore());
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('방향 분석'));
      await tester.pumpAndSettle();

      expect(find.text('어디로 향하고 있나'), findsWidgets);
      expect(find.textContaining(aiDisclosure), findsNothing);
    });

    testWidgets('counts 알고리즘 검증 as read and opens the log', (tester) async {
      final tips = InMemoryTipStore();
      await pumpMatch(tester, tips: tips, platform: TargetPlatform.iOS);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.tap(find.text('알고리즘 검증'));
      await tester.pumpAndSettle();

      expect(find.textContaining('axisWeights'), findsOneWidget);
      expect(await tips.load(), contains(TipIds.aiDisclosure));
    });

    // A tab the shell has built offstage is not a visit.
    testWidgets('waits while the tab is offstage', (tester) async {
      final tips = InMemoryTipStore();
      await pumpMatch(tester, tips: tips, onScreen: false);

      expect(find.textContaining(aiDisclosure), findsNothing);
      expect(await tips.load(), isNot(contains(TipIds.aiDisclosure)));
    });

    testWidgets('is skipped when already dismissed', (tester) async {
      await pumpMatch(tester, tips: InMemoryTipStore({TipIds.aiDisclosure}));

      expect(find.textContaining(aiDisclosure), findsNothing);
    });
  });

  group('the header', () {
    testWidgets('says how much text the result rests on, and when', (
      tester,
    ) async {
      await pumpMatch(tester);

      expect(find.text('나에게 유리한 후보는?'), findsWidgets);
      expect(find.text('서울 마포구 을'), findsOneWidget);
      expect(find.text('대조한 공약 42건 · 7월 30일 산출'), findsOneWidget);
    });

    testWidgets('links the meta line to the weights', (tester) async {
      await pumpMatch(tester);

      await tester.tap(find.text('가중치와 입력값'));
      await tester.pumpAndSettle();

      expect(find.textContaining('axisWeights'), findsOneWidget);
    });

    testWidgets('switches to the direction analysis and back', (tester) async {
      await pumpMatch(tester);

      await tester.tap(find.text('방향 분석'));
      await tester.pumpAndSettle();
      expect(find.text('어디로 향하고 있나'), findsWidgets);

      await tester.tap(find.text('후보 매칭'));
      await tester.pumpAndSettle();
      expect(find.text('나에게 유리한 후보는?'), findsWidgets);
      expect(find.text('어디로 향하고 있나'), findsNothing);
    });
  });

  group('the native chrome', () {
    testWidgets('android: a large app bar and M3 segments', (tester) async {
      await pumpMatch(tester);

      expect(find.byType(SliverAppBar), findsOneWidget);
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('ios: the title on the page, no app bar', (tester) async {
      await pumpMatch(tester, platform: TargetPlatform.iOS);

      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.text('나에게 유리한 후보는?'), findsOneWidget);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('${platform.name}: the notice leads to the weights', (
        tester,
      ) async {
        await pumpMatch(tester, platform: platform);

        await tester.tap(_action(platform, 'AI 분석 안내'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('알고리즘 검증'));
        await tester.pumpAndSettle();
        expect(find.textContaining('axisWeights'), findsOneWidget);

        // The log is a pushed page with the platform's own way back.
        await tester.tap(_action(platform, '뒤로').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('axisWeights'), findsNothing);
        expect(find.text('나에게 유리한 후보는?'), findsWidgets);
      });
    }
  });

  group('the ranking', () {
    testWidgets('leads with the top match and its score', (tester) async {
      await pumpMatch(tester);

      expect(find.text('1위 매칭', findRichText: true), findsOneWidget);
      expect(find.text('87점', findRichText: true), findsOneWidget);
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

    testWidgets('draws one bar per axis for the leader only', (tester) async {
      await pumpMatch(tester);

      for (final label in ['세금', '부동산', '복지', '교육', '청년']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('92'), findsOneWidget);
    });

    // Only the leader gets the bars; the others are a row. A
    // second full card would read as a comparison between candidates rather
    // than between each candidate and the reader.
    testWidgets('gives the runners-up a row, not a second card', (
      tester,
    ) async {
      await pumpMatch(tester);
      await tester.scrollUntilVisible(
        find.text('3위'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('73점', findRichText: true), findsOneWidget);
      expect(find.text('61점', findRichText: true), findsOneWidget);
      expect(find.text('2위'), findsOneWidget);
      expect(find.text('3위'), findsOneWidget);
      expect(find.text('2위 매칭', findRichText: true), findsNothing);
    });
  });

  group('the reasoning', () {
    testWidgets('arrives as a stream and lands on the full text', (
      tester,
    ) async {
      await pumpMatch(tester);

      await openReasoning(tester);

      expect(find.textContaining('간이과세 기준 상향'), findsOneWidget);
    });

    testWidgets('numbers each reason', (tester) async {
      await pumpMatch(tester);

      await openReasoning(tester);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('1인 가구 대상 주거비'), findsOneWidget);
      expect(find.text('원문 대조 보기 ↗'), findsOneWidget);
    });

    // Tapping an axis is a request to see why.
    testWidgets('opens when an axis is tapped', (tester) async {
      await pumpMatch(tester);
      expect(find.textContaining('간이과세 기준 상향'), findsNothing);

      await tester.tap(find.text('세금'));
      await tester.pumpAndSettle();

      expect(find.textContaining('간이과세 기준 상향'), findsOneWidget);
    });

    // A model explaining itself is not evidence; the pledge text is.
    testWidgets('carries a source for every claim it makes', (tester) async {
      await pumpMatch(tester);

      await openReasoning(tester);

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

    testWidgets('the label refuses to build without it too', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: const AiReferenceLabel(),
        ),
      );

      expect(tester.takeException(), isA<MissingDisclosureScopeException>());
    });

    // The residue a type cannot express -- that the marking is on screen at
    // the moment a reader is looking at a score -- is pinned by 'labels every
    // score it shows' above.
  });
}

/// A toolbar action by its label: the Material tooltip on Android, the glass
/// button's semantics label on iOS.
Finder _action(TargetPlatform platform, String label) =>
    platform == TargetPlatform.android
    ? find.byTooltip(label)
    : find.bySemanticsLabel(label);
