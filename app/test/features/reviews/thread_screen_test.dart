import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/application/thread_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/data/remote_thread_repository.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:democracy/src/features/reviews/presentation/thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _home = DistrictRef(id: 'fixture-seoul-mapo-b', displayName: '서울 마포구 을');
const _elsewhere = DistrictRef(
  id: 'fixture-seoul-mapo-a',
  displayName: '서울 마포구 갑',
);

void main() {
  Future<FakeThreadRepository> pumpThread(
    WidgetTester tester, {
    String id = 'fixture-thread-1',
    bool verified = false,
    DistrictRef district = _home,
    String? start,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loader = fixtureLoaderFromDisk();
    final threads = FakeThreadRepository(loader: loader);
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        districtRepositoryProvider.overrideWithValue(
          FakeDistrictRepository(loader: loader),
        ),
        reviewRepositoryProvider.overrideWithValue(
          FakeReviewRepository(loader: loader),
        ),
        communityRepositoryProvider.overrideWithValue(
          FakeCommunityRepository(loader: loader),
        ),
        threadRepositoryProvider.overrideWithValue(threads),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(addressControllerProvider.notifier);
    if (verified) {
      controller.acceptVerification(
        district: district,
        proof: ResidencyVerificationProof(
          opaqueToken: 'fixture-token',
          verifiedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    } else {
      controller.continueReadOnly(district: district);
    }

    final router = GoRouter(
      initialLocation: start ?? AppRoutes.threadDetail(id),
      routes: [
        GoRoute(
          path: AppRoutes.community,
          builder: (context, state) => const CommunityScreen(),
          routes: [
            GoRoute(
              path: AppRoutes.threadDetailSegment,
              builder: (context, state) =>
                  ThreadScreen(threadId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return threads;
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens from the 정책 토론 list', (tester) async {
    await pumpThread(tester, start: AppRoutes.community);
    await tester.tap(find.text('정책 토론'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thread-fixture-thread-1')));
    await tester.pumpAndSettle();

    expect(find.byType(ThreadScreen), findsOneWidget);
    expect(find.text('역세권 청년주택 공급 촉진법 개정안'), findsOneWidget);
  });

  testWidgets('shows the bill, its source, and the replies oldest first', (
    tester,
  ) async {
    await pumpThread(tester);

    for (final text in ['가상 의원의원 등 10인', '국토교통위원회', '위원회 심사', '2026. 7. 21.']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('출처 likms.assembly.go.kr'), findsOneWidget);
    expect(find.text('4개'), findsOneWidget);
    expect(find.text('신고로 가려진 글입니다.'), findsOneWidget);
    // KST, whatever the device zone: 01:12Z is 10:12 in Seoul.
    expect(find.text('7월 28일 10:12'), findsOneWidget);
    final first = tester.getTopLeft(find.textContaining('공급 물량 기준이'));
    final second = tester.getTopLeft(find.text('합정역 주변이 대상에 들어가는지 궁금합니다.'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('says when there are no replies yet', (tester) async {
    await pumpThread(tester, id: 'fixture-thread-3');
    expect(find.text('아직 답글이 없습니다.'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
  });

  testWidgets('an unverified reader gets the gate, not a dead field', (
    tester,
  ) async {
    await pumpThread(tester);
    expect(find.text('이 지역구 주소 인증 주민만 쓸 수 있습니다'), findsOneWidget);
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    expect(find.text('글쓰기 전에'), findsOneWidget);
  });

  testWidgets('a resident of another district cannot reply here', (
    tester,
  ) async {
    final threads = await pumpThread(
      tester,
      verified: true,
      district: _elsewhere,
    );
    expect(find.text('이 지역구 주소 인증 주민만 쓸 수 있습니다'), findsOneWidget);
    await tester.tap(find.byTooltip('보내기'));
    await tester.pumpAndSettle();
    final page = await threads.load('fixture-thread-1');
    expect(page.replies, hasLength(4));
  });

  testWidgets('a resident replies, sees it as theirs, and can delete it', (
    tester,
  ) async {
    await pumpThread(tester, verified: true);
    await send(tester, '검토보고서 링크 공유합니다.');

    expect(find.text('검토보고서 링크 공유합니다.'), findsOneWidget);
    expect(find.text('익명 주민 (나)'), findsOneWidget);
    expect(find.text('5개'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('reply-menu-local-fixture-thread-1-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('검토보고서 링크 공유합니다.'), findsNothing);
    expect(find.text('4개'), findsOneWidget);
  });

  testWidgets('will not send a reply with a hate term', (tester) async {
    final threads = await pumpThread(tester, verified: true);
    await send(tester, '멍청한 법안');
    expect(find.textContaining('혐오 표현으로 감지된'), findsOneWidget);
    expect((await threads.load('fixture-thread-1')).replies, hasLength(4));
  });
}
