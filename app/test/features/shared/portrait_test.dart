import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(TargetPlatform.android),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('no photo: the placeholder, named for the reader', (
    tester,
  ) async {
    await tester.pumpWidget(host(const GrayscalePortrait(name: '가상 의원')));

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.bySemanticsLabel('가상 의원 사진'), findsOneWidget);
  });

  testWidgets('a photo that fails to load falls back to the placeholder', (
    tester,
  ) async {
    // The test binding answers every network image with an error.
    await tester.pumpWidget(
      host(
        const GrayscalePortrait(
          name: '가상 의원',
          imageUrl:
              'https://example.supabase.co/storage/v1/object/public/portraits/members/a.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    // Still desaturated: the filter wraps the photo, not just the placeholder.
    expect(
      find.ancestor(
        of: find.byType(Image),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
  });

  test('a politician carries the credit the server sent with the photo', () {
    final p = Politician.fromJson({
      'id': 'm1',
      'name': '가상 의원',
      'portraitUrl': 'https://example/p.jpg',
      'portraitCredit': '사진: 국회사무처 (공공누리 제1유형)',
    });
    expect(p.portraitCredit, '사진: 국회사무처 (공공누리 제1유형)');
  });
}
