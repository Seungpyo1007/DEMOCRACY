import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/features/history/application/history_providers.dart';
import 'package:democracy/src/features/history/data/fake_history_repository.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:democracy/src/features/history/domain/history_repository.dart';
import 'package:democracy/src/features/history/presentation/history_screen.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

/// Serves a payload built by the test, through the real parser.
class _PayloadRepository implements HistoryRepository {
  const _PayloadRepository(this.payload);

  final Map<String, Object?> payload;

  @override
  Future<HistoryRecord> loadHistory(String districtId) async =>
      HistoryRecord.fromJson(payload);
}

class _FailingRepository implements HistoryRepository {
  const _FailingRepository(this.error);

  final Object error;

  @override
  Future<HistoryRecord> loadHistory(String districtId) async => throw error;
}

void main() {
  Future<GoRouter> pumpHistory(
    WidgetTester tester, {
    HistoryRepository? repository,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        historyRepositoryProvider.overrideWithValue(
          repository ?? FakeHistoryRepository(loader: fixtureLoaderFromDisk()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    final router = GoRouter(
      initialLocation: AppRoutes.history,
      routes: [
        GoRoute(
          path: AppRoutes.history,
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: AppRoutes.results,
          builder: (context, state) => const Text('개표 화면'),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Text('홈 화면'),
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
    return router;
  }

  Finder sectionHeader(String label) => find.byWidgetPredicate(
    (widget) => widget is SectionHeader && widget.label == label,
  );

  /// Where the section switch ends: sections land just below it. Android
  /// pins it as a bar under the app bar; iOS floats it in the tool row.
  double anchorBarBottom(WidgetTester tester) {
    final pinned = find.ancestor(
      of: find.byType(AppSegmentedControl),
      matching: find.byType(SliverPersistentHeader),
    );
    if (pinned.evaluate().isNotEmpty) {
      return tester
          .getBottomLeft(
            find
                .descendant(of: pinned, matching: find.byType(DecoratedBox))
                .first,
          )
          .dy;
    }
    return tester.getBottomLeft(find.byType(AppSegmentedControl)).dy;
  }

  /// A section jumped to sits just under the pinned bar, not under it.
  Matcher justBelow(double edge) =>
      allOf(greaterThanOrEqualTo(edge - 1), lessThan(edge + 24));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('renders the three sections, each with its source '
        '(${platform.name})', (tester) async {
      await pumpHistory(tester, platform: platform);

      // Android's large app bar sets the title twice (expanded, collapsed).
      expect(
        find.text('역사'),
        platform == TargetPlatform.android ? findsWidgets : findsOneWidget,
      );
      expect(find.text('서울 마포구 을'), findsOneWidget);
      expect(find.text('한 지역구가 걸어온 길'), findsOneWidget);

      expect(sectionHeader('지역의 역사'), findsOneWidget);
      expect(sectionHeader('선거의 역사'), findsOneWidget);
      expect(sectionHeader('의원 연대기'), findsOneWidget);

      expect(find.text('마포구 설치'), findsOneWidget);
      expect(find.text('경의선 숲길 전 구간 개통'), findsOneWidget);
      expect(find.text('가상 인물 라'), findsOneWidget);
      expect(find.text('도시공원 보전 및 이용에 관한 법률 개정안'), findsOneWidget);

      // One badge per publisher: district office, commission, assembly.
      expect(find.byType(SourceBadge), findsNWidgets(3));
      expect(find.text('득표율은 당선자 기준'), findsOneWidget);
    });
  }

  testWidgets('an unknown year says so instead of printing one', (
    tester,
  ) async {
    await pumpHistory(tester);

    expect(find.text('1944'), findsOneWidget);
    expect(find.text('연도 미상'), findsOneWidget);
  });

  testWidgets('the chart is read out as its values', (tester) async {
    await pumpHistory(tester);

    expect(
      find.bySemanticsLabel('당선 득표율 2016년 44.1%, 2020년 46.8%, 2024년 45.2%'),
      findsOneWidget,
    );
    expect(find.text('45.2%', findRichText: true), findsWidgets);
  });

  testWidgets('party tags are grey and portraits grayscale', (tester) async {
    await pumpHistory(tester);

    // 3 winners in the table + the incumbent's header.
    expect(find.byType(PartyTag), findsNWidgets(4));
    expect(find.byType(GrayscalePortrait), findsOneWidget);
  });

  testWidgets('the first-win note sits on the 2020 row only', (tester) async {
    await pumpHistory(tester);

    final note = find.text('첫 당선');
    expect(note, findsOneWidget);
    final row = find.ancestor(of: note, matching: find.byType(RuledRow));
    expect(
      find.descendant(of: row, matching: find.text('2020')),
      findsOneWidget,
    );
  });

  testWidgets('the first-win note is computed from the rows', (tester) async {
    final payload =
        json.decode(
              File(
                'assets/fixtures/history_fixture-seoul-mapo-b.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final rows =
        (payload['elections']! as Map<String, Object?>)['rows']! as List;
    (rows[1] as Map<String, Object?>)['winner'] = {
      'id': 'fixture-other',
      'name': '가상 인물 마',
      'party': '다라당',
    };

    await pumpHistory(tester, repository: _PayloadRepository(payload));

    final row = find.ancestor(
      of: find.text('첫 당선'),
      matching: find.byType(RuledRow),
    );
    expect(
      find.descendant(of: row, matching: find.text('2024')),
      findsOneWidget,
    );
  });

  testWidgets('the ongoing election opens the results tab', (tester) async {
    final router = await pumpHistory(tester);

    final current = find.text('개표 중');
    // Mid-screen: at the very top it would sit under the floating tool row.
    await Scrollable.ensureVisible(tester.element(current), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(current);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.results,
    );
    expect(find.text('개표 화면'), findsOneWidget);
  });

  testWidgets('anchor segments scroll to their section and mark it', (
    tester,
  ) async {
    await pumpHistory(tester);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);
    expect(tester.getSemantics(find.text('지역')), isSemantics(isSelected: true));

    await tester.tap(find.text('선거'));
    await tester.pumpAndSettle();

    final electionTop = tester.getTopLeft(sectionHeader('선거의 역사')).dy;
    expect(scrollable.position.pixels, greaterThan(0));
    expect(electionTop, justBelow(anchorBarBottom(tester)));
    expect(tester.getSemantics(find.text('선거')), isSemantics(isSelected: true));
    expect(
      tester.getSemantics(find.text('지역')),
      isNot(isSemantics(isSelected: true)),
    );

    // The bar is pinned, so the next segment is reachable without scrolling
    // back up.
    await tester.tap(find.text('의원'));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.text('의원')), isSemantics(isSelected: true));
    expect(tester.getTopLeft(sectionHeader('의원 연대기')).dy, lessThan(844 / 2));
  });

  testWidgets('segments jump without animation under reduced motion', (
    tester,
  ) async {
    await pumpHistory(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    await tester.tap(find.text('선거'));
    await tester.pump();

    expect(
      tester.getTopLeft(sectionHeader('선거의 역사')).dy,
      justBelow(anchorBarBottom(tester)),
    );
  });

  testWidgets('the anchor bar stays pinned and tracks the section in view', (
    tester,
  ) async {
    await pumpHistory(tester);
    final scrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text('가상 인물 라'),
      300,
      scrollable: scrollable,
    );
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Still on screen at the top, over the content.
    expect(find.byType(AppSegmentedControl).hitTestable(), findsOneWidget);
    expect(anchorBarBottom(tester), lessThan(120));
    expect(tester.getSemantics(find.text('의원')), isSemantics(isSelected: true));

    await tester.fling(scrollable, const Offset(0, 4000), 4000);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('지역')), isSemantics(isSelected: true));
  });

  testWidgets('Android: M3 large app bar and segmented button', (tester) async {
    await pumpHistory(tester, platform: TargetPlatform.android);

    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);

    await tester.tap(find.text('선거'));
    await tester.pumpAndSettle();

    final button = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(button.selected, {1});
    expect(
      tester.getTopLeft(sectionHeader('선거의 역사')).dy,
      justBelow(anchorBarBottom(tester)),
    );
  });

  testWidgets('an unsourced payload is refused, not drawn', (tester) async {
    await pumpHistory(
      tester,
      repository: const _FailingRepository(
        MissingSourceException(field: 'region', reason: 'no source'),
      ),
    );

    expect(find.text('출처가 확인되지 않아 표시하지 않습니다.'), findsOneWidget);
    expect(sectionHeader('지역의 역사'), findsNothing);
  });
}
