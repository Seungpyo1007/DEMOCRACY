import 'package:democracy/src/app/democracy_app.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The whole app, with the one thing a test must not reach -- the Keychain
  /// -- swapped for a store held in memory. The store is handed in rather than
  /// created here so a test can start from a session a previous launch left.
  Future<void> launch(WidgetTester tester, InMemoryAddressStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [addressStoreProvider.overrideWithValue(store)],
        child: const DemocracyApp(),
      ),
    );
    // Bounded rather than settled. A launch that restores a district opens on
    // the dashboard, and the dashboard is one of the screens this suite
    // already pumps by hand: something on it is always animating, so
    // pumpAndSettle has nothing to settle to.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('continues from onboarding to the read-only home', (
    tester,
  ) async {
    await launch(tester, InMemoryAddressStore());

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

  // Setting a district is a one-time act in the product. Before the address
  // was persisted the app behaved as though it were a per-launch one: the
  // second launch found nothing and the router sent the resident back through
  // onboarding, verification and all.
  testWidgets('a second launch opens on the home, not on onboarding', (
    tester,
  ) async {
    // Seeded rather than driven through onboarding a second time: that
    // onboarding writes this record is address_store_test's job, and what is
    // under test here is only where a launch that finds one lands.
    await launch(
      tester,
      InMemoryAddressStore(
        const AddressState.readOnly(
          district: DistrictRef(
            id: 'fixture-seoul-mapo-b',
            displayName: '서울 마포구 을',
          ),
        ),
      ),
    );

    expect(find.textContaining('내 지역구부터'), findsNothing);
    expect(find.text('서울 마포구 을'), findsOneWidget);
  });
}
