import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocks an unverified write action', (tester) async {
    var calls = 0;
    var verificationRequests = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VerifiedGate(
              onVerificationRequested: () => verificationRequests += 1,
              onVerified: () => calls += 1,
              builder: (context, onPressed) {
                return FilledButton(
                  onPressed: onPressed,
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('실행'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('주민 인증이 필요합니다'), findsOneWidget);

    await tester.tap(find.text('인증하러 가기'));
    await tester.pumpAndSettle();

    expect(verificationRequests, 1);
  });

  testWidgets('runs a verified write action once', (tester) async {
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(addressControllerProvider.notifier)
        .acceptVerification(
          district: const DistrictRef(
            id: 'fixture-seoul-mapo-b',
            displayName: '서울 마포구 을',
          ),
          proof: ResidencyVerificationProof(
            opaqueToken: 'fixture-opaque-token',
            verifiedAt: DateTime.utc(2026, 7, 30),
          ),
        );
    var calls = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VerifiedGate(
              onVerificationRequested: () {},
              onVerified: () => calls += 1,
              builder: (context, onPressed) {
                return FilledButton(
                  onPressed: onPressed,
                  child: const Text('실행'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('실행'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('주민 인증이 필요합니다'), findsNothing);
  });
}
