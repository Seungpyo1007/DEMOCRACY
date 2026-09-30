import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/features/results/application/results_providers.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/presentation/count_map.dart';
import 'package:democracy/src/features/results/presentation/election_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/national_results.dart';

class _OnceRepository implements ResultsRepository {
  const _OnceRepository(this.payload);

  final Map<String, Object?> payload;

  @override
  Stream<RawElectionResults> watch(String districtId) =>
      Stream.value(RawElectionResults.fromJson(payload));
}

/// The fixture has six districts; the BFF sends 254. These pin down that the
/// screen stays usable at that size and says truthfully what it is showing.
void main() {
  final home = DistrictRef(
    id: nationalDistrictId('경기', 7),
    displayName: '경기 가상7구',
  );

  Future<void> pumpNational(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        clockProvider.overrideWithValue(
          FixedClock(KstInstant.seoul(2026, 9, 27, 12)),
        ),
        resultsRepositoryProvider.overrideWithValue(
          _OnceRepository(nationalResultsPayload()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: home);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(platform),
          home: const ElectionResultsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('254 districts: one 시도 at a time, the reader\'s first '
        '(${platform.name})', (tester) async {
      await pumpNational(tester, platform: platform);

      expect(tester.takeException(), isNull);
      final map = tester.widget<CountMap>(find.byType(CountMap));
      expect(map.districts, hasLength(60));
      expect(
        map.districts.every((d) => d.districtName.startsWith('경기 ')),
        true,
      );
      expect(find.text('내 지역구'), findsOneWidget);
      // The panel opens on the reader's district.
      expect(find.text('경기 가상7구'), findsOneWidget);
      expect(find.text('서울'), findsOneWidget);
      expect(find.text('제주'), findsOneWidget);
      // The chip row has been scrolled to the reader's 시도.
      final chip = tester.getRect(
        find.byWidgetPredicate((w) => w is AppFilterChip && w.label == '경기'),
      );
      expect(chip.left, greaterThanOrEqualTo(0));
      expect(chip.right, lessThanOrEqualTo(390));
    });
  }

  testWidgets('a 시도 chip moves the map and the panel', (tester) async {
    await pumpNational(tester);

    // The row starts on the reader's 시도; 제주 is further along it.
    await tester.ensureVisible(find.text('제주'));
    await tester.tap(find.text('제주'));
    await tester.pumpAndSettle();

    final map = tester.widget<CountMap>(find.byType(CountMap));
    expect(map.districts.map((d) => d.districtName), [
      '제주 가상1구',
      '제주 가상2구',
      '제주 가상3구',
    ]);
    expect(find.text('제주 가상1구'), findsOneWidget);
    expect(find.textContaining('내 지역구'), findsNothing);
  });

  testWidgets('a final count is not called live, and its order is stated', (
    tester,
  ) async {
    await pumpNational(tester);

    expect(find.text('개표 결과'), findsWidgets);
    expect(find.text('실시간 개표'), findsNothing);
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('득표율 높은 순'), findsOneWidget);
    // Highest share first, whatever order the wire used.
    final names = find.textContaining('가상 후보');
    expect(tester.widget<Text>(names.first).data, '가상 후보 가');
  });

  testWidgets('no polls says so rather than drawing an empty chart', (
    tester,
  ) async {
    await pumpNational(tester);

    await tester.tap(find.text('여론조사 비교'));
    await tester.pumpAndSettle();

    expect(find.text('표시할 여론조사가 없습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('poll-chart')), findsNothing);
  });
}
