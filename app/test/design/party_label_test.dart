import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/party_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TargetPlatform.android),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Color textColorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  group('onColor', () {
    test('clears WCAG AA on every colour, light, dark or mid-tone', () {
      final colors = <Color>[
        // The sourced party colours in KoreaPoliticsAPI parties.json.
        const Color(0xFF003B95),
        const Color(0xFFE61E2B),
        const Color(0xFF0073CF),
        const Color(0xFFD6001C),
        const Color(0xFFFF7210),
        const Color(0xFF00D2C3),
        const Color(0xFFF58400),
        const Color(0xFFFFED00),
        const Color(0xFF007C36),
        const Color(0xFF51BDC5),
        const Color(0xFF009944),
        const Color(0xFFFF0000),
        const Color(0xFF73B247),
        const Color(0xFF1C1F87),
        // And the hard cases: mid greys and saturated mid-tones.
        const Color(0xFF777777),
        const Color(0xFF808080),
        const Color(0xFF2196F3),
        const Color(0xFF00FF00),
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      ];
      for (final c in colors) {
        final on = PartyLabel.onColor(c);
        expect(
          PartyLabel.contrast(c, on),
          greaterThanOrEqualTo(PartyLabel.minContrast),
          reason: '${c.toARGB32().toRadixString(16)} → $on',
        );
      }
    });

    test('prefers the app ink and white over pure black', () {
      expect(PartyLabel.onColor(const Color(0xFFFFED00)), AppColors.ink);
      expect(PartyLabel.onColor(const Color(0xFF003B95)), AppColors.white);
    });
  });

  testWidgets('a coloured tag fills with the colour and keeps the name', (
    tester,
  ) async {
    await pump(tester, const PartyLabel(name: '가나당', color: Color(0xFFFFED00)));

    expect(find.text('가나당'), findsOneWidget);
    expect(textColorOf(tester, '가나당'), AppColors.ink);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('가나당'), matching: find.byType(DecoratedBox)),
    );
    expect((box.decoration as BoxDecoration).color, const Color(0xFFFFED00));
  });

  testWidgets('no colour is the neutral outline', (tester) async {
    await pump(tester, const PartyLabel(name: '무소속'));

    expect(textColorOf(tester, '무소속'), AppColors.neutral700);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('무소속'), matching: find.byType(DecoratedBox)),
    );
    expect((box.decoration as BoxDecoration).color, isNull);
  });

  testWidgets('the side is a written mark, read out in full', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const PartyLabel(
        name: '가나당',
        color: Color(0xFF1A4B8C),
        sideMark: '여',
        sideLabel: '여당',
      ),
    );

    expect(find.text('여'), findsOneWidget);
    expect(find.bySemanticsLabel('가나당, 여당'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a long name ellipsizes in a bounded row, mark and all', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 120,
        child: Row(
          children: [
            Flexible(
              child: PartyLabel(
                name: '아주아주아주아주긴이름의가상정당',
                color: Color(0xFF1A4B8C),
                sideMark: '야',
                sideLabel: '야당',
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('야'), findsOneWidget);
  });
}
