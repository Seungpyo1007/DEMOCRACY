import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/data/fake_results_repository.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/presentation/count_map.dart';
import 'package:democracy/src/features/results/presentation/election_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

void main() {
  /// The LIVE dot pulses forever, so `pumpAndSettle` never returns on this
  /// screen. A bounded pump is the honest way to wait for one that is
  /// deliberately never at rest.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<ProviderContainer> pumpResults(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        resultsRepositoryProvider.overrideWithValue(
          FakeResultsRepository(
            loader: fixtureLoaderFromDisk(),
            // The polling cadence is the server's business; what is under
            // test is the screen.
            interval: Duration.zero,
            ticks: 0,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: const ElectionResultsScreen(),
        ),
      ),
    );
    await settle(tester);
    return container;
  }

  group('the map', () {
    // N-1 made structural: nothing but the counted share reaches the fill, so
    // the map cannot become a map of who is ahead.
    test('shades only by how much has been counted', () {
      expect(
        CountMap.shadeFor(0.9).computeLuminance(),
        lessThan(CountMap.shadeFor(0.1).computeLuminance()),
      );
      expect(CountMap.shadeFor(0), AppColors.neutral200);
      expect(CountMap.shadeFor(1), AppColors.ink);
    });

    testWidgets('reads out the count for a reader who cannot see the shade', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpResults(tester);

      expect(find.bySemanticsLabel('서울 마포구 을, 개표 71%'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('selecting a district moves the panel to it', (tester) async {
      await pumpResults(tester);
      expect(find.textContaining('서울 마포구 을 · 개표 71%'), findsOneWidget);

      await tester.tap(find.text('82'));
      await settle(tester);

      expect(find.textContaining('서울 서대문구 갑 · 개표 82%'), findsOneWidget);
    });
  });

  group('the panel', () {
    testWidgets('ranks by share and carries a source', (tester) async {
      await pumpResults(tester);

      expect(find.text('48.2%'), findsOneWidget);
      expect(find.text('44.7%'), findsOneWidget);
      expect(find.text('7.1%'), findsOneWidget);
      expect(find.textContaining('출처: info.nec.go.kr'), findsWidgets);
    });

    testWidgets('switches between live, historical and polls', (tester) async {
      await pumpResults(tester);

      await tester.tap(find.textContaining('역대 결과'));
      await settle(tester);
      expect(find.text('역대 득표율'), findsOneWidget);

      await tester.tap(find.textContaining('여론조사'));
      await settle(tester);
      expect(find.text('여론조사 비교'), findsOneWidget);
    });

    // The guide requires the distinction to be visible at all times, so it is
    // a field on the series rather than a styling choice at the call site.
    testWidgets('marks the app poll as not accredited, every time', (
      tester,
    ) async {
      await pumpResults(tester);

      await tester.tap(find.textContaining('여론조사'));
      await settle(tester);

      expect(find.text('한국갤럽 · 공인 조사'), findsOneWidget);
      expect(find.text('앱 내 조사 · 공인 조사 아님'), findsOneWidget);
      expect(find.textContaining('공인 조사가 아닙니다'), findsOneWidget);
    });
  });

  group('a count that only rises', () {
    test('never reports a district going backwards', () async {
      final repository = FakeResultsRepository(
        loader: fixtureLoaderFromDisk(),
        interval: Duration.zero,
        ticks: 4,
      );

      final seen = <double>[];
      await for (final results in repository.watch(_district.id)) {
        seen.add(results.byId(_district.id)!.countedShare);
      }

      expect(seen.length, 5);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      expect(seen.last, lessThanOrEqualTo(100));
    });

    // A longer count changes confidence, not the split. Inventing movement
    // would be the stand-in asserting something about an election.
    test('holds the shares still while the count advances', () async {
      final repository = FakeResultsRepository(
        loader: fixtureLoaderFromDisk(),
        interval: Duration.zero,
        ticks: 3,
      );

      final shares = <List<double>>[];
      await for (final results in repository.watch(_district.id)) {
        shares.add(
          results
              .byId(_district.id)!
              .tallies
              .map((tally) => tally.share)
              .toList(),
        );
      }

      for (final row in shares) {
        expect(row, shares.first);
      }
    });
  });

  group('the poll series', () {
    test('defaults to not accredited when the payload is silent', () {
      final series = PollSeries.fromJson(const {
        'label': '출처 미상 조사',
        'points': <Object?>[],
      });

      expect(series.accredited, isFalse);
      expect(series.caption, contains('공인 조사 아님'));
    });
  });
}
