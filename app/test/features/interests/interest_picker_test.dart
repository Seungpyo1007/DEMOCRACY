import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/interests/presentation/interest_picker.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<InterestSelection? Function()> open(
    WidgetTester tester, {
    required ResidentProfile initial,
    bool withContext = false,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    InterestSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showInterestPicker(
                  context,
                  initial: initial,
                  withContext: withContext,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return () => result;
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(InterestPicker),
        matching: find.byType(EditableText),
      ),
      query,
    );
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a sixth pick is refused and says why, on ${platform.name}', (
      tester,
    ) async {
      final result = await open(
        tester,
        platform: platform,
        initial: const ResidentProfile(
          topics: [
            'transport.rail',
            'housing.rent',
            'education',
            'welfare',
            'youth',
          ],
        ),
      );
      expect(find.text('5/5'), findsOneWidget);

      await search(tester, 'ㅂㅅ');
      await tester.tap(find.text('버스'));
      await tester.pumpAndSettle();
      expect(find.text('5개까지 고를 수 있습니다. 하나를 빼고 다시 고르세요.'), findsOneWidget);

      // Taking one out makes room.
      await tester.tap(find.bySemanticsLabel('청년 빼기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('버스'));
      await tester.pumpAndSettle();
      expect(find.text('5/5'), findsOneWidget);

      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(result()!.topics, [
        'transport.rail',
        'transport.bus',
        'housing.rent',
        'education',
        'welfare',
      ]);
    });
  }

  testWidgets('browses by 분야: a row opens to the whole 분야 and its topics', (
    tester,
  ) async {
    final result = await open(tester, initial: const ResidentProfile());

    expect(find.text('지하철·광역철도'), findsNothing);
    await tester.tap(find.text('교통'));
    await tester.pumpAndSettle();
    expect(find.text('교통 전체'), findsOneWidget);
    await tester.tap(find.text('지하철·광역철도'));
    await tester.pumpAndSettle();
    expect(find.text('1개 고름'), findsOneWidget);

    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(result()!.topics, ['transport.rail']);
  });

  testWidgets('shows each result with its 분야, and says when none match', (
    tester,
  ) async {
    await open(tester, initial: const ResidentProfile());

    await search(tester, 'GTX');
    expect(find.text('지하철·광역철도'), findsOneWidget);
    expect(find.text('교통 분야'), findsOneWidget);

    await search(tester, '우주여행');
    expect(find.text('‘우주여행’에 맞는 관심사가 없습니다.'), findsOneWidget);
  });

  testWidgets('on the AI tab it edits the context chips too', (tester) async {
    final result = await open(
      tester,
      withContext: true,
      initial: const ResidentProfile(context: {'30대'}),
    );

    await tester.tap(find.text('자영업'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(result()!.context, {'30대', '자영업'});
  });

  testWidgets('dismissed without 적용, nothing changes', (tester) async {
    final result = await open(
      tester,
      initial: const ResidentProfile(topics: ['pets']),
    );
    await search(tester, 'ㅂㅅ');
    await tester.tap(find.text('버스'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
