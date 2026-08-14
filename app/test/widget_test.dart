import 'package:democracy/src/app/democracy_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continues from onboarding to the read-only home', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DemocracyApp()));
    await tester.pumpAndSettle();

    expect(find.textContaining('내 지역구부터'), findsOneWidget);

    // Skipping verification still needs a district: every screen past
    // onboarding is about one, and the router turns a district-less user
    // around. Location is the one-tap way to get one.
    await tester.tap(find.text('현재 위치(GPS)로 자동 설정'));
    await tester.pumpAndSettle();
    expect(find.text('서울 마포구 을'), findsOneWidget);

    await tester.tap(find.text('나중에 인증하기'));
    await tester.pumpAndSettle();

    expect(find.text('서울 마포구 을'), findsOneWidget);
    expect(find.text('읽기 전용'), findsOneWidget);
    for (final tab in const ['트래커', 'AI 분석', '커뮤니티', '개표']) {
      expect(find.text(tab), findsOneWidget);
    }
  });
}
