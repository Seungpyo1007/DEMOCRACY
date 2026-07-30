import 'package:democracy/src/app/democracy_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continues from onboarding to the read-only home', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DemocracyApp()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('주소 인증'), findsOneWidget);

    await tester.tap(find.text('나중에 인증하기'));
    await tester.pumpAndSettle();

    expect(find.text('서울 마포구 을'), findsOneWidget);
    expect(find.text('읽기 전용'), findsOneWidget);
    expect(find.text('트래커'), findsOneWidget);
    expect(find.text('AI 분석'), findsOneWidget);
    expect(find.text('커뮤니티'), findsOneWidget);
    expect(find.text('개표'), findsOneWidget);
  });
}
