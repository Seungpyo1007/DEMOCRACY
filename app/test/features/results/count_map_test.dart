import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/results/domain/election_results.dart';
import 'package:democracy/src/features/results/presentation/count_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real 선거구 names, not the fixtures' short 가상N구: merged districts run
/// well past a tile's width, and the grid has to stay legible anyway.
void main() {
  final source = SourceMetadata(
    sourceUrl: Uri.parse('https://www.data.go.kr/'),
    fetchedAt: DateTime.utc(2024, 4, 11),
  );

  DistrictCount count(String id, String name) => DistrictCount(
    districtId: id,
    districtName: name,
    countedShare: 1,
    tallies: const [],
    source: source,
  );

  // Thirteen, so the grid is the dense three-column one.
  final districts = [
    count('a', '경기 동두천시양주시연천군 갑'),
    count('b', '경기 동두천시양주시연천군 을'),
    for (var i = 0; i < 11; i++) count('n$i', '경기 성남시분당구 ${'갑을'[i % 2]}'),
  ];

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TargetPlatform.android),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CountMap(
              districts: districts,
              selectedId: 'b',
              homeId: 'a',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps 갑 and 을 when a long name is cut', (tester) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('동두천시양주시연천군'), findsNWidgets(2));
    expect(find.text(' 갑'), findsWidgets);
    expect(find.text(' 을'), findsWidgets);
    expect(find.text('내 지역구'), findsOneWidget);
  });

  testWidgets('grows its tiles with the text size', (tester) async {
    await pump(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
  });
}
