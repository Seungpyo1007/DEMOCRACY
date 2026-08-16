import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:democracy/src/features/reviews/presentation/review_compose_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

void main() {
  Future<ProviderContainer> pumpCommunity(
    WidgetTester tester, {
    bool verified = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loader = fixtureLoaderFromDisk();
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        reviewRepositoryProvider.overrideWithValue(
          FakeReviewRepository(loader: loader),
        ),
        communityRepositoryProvider.overrideWithValue(
          FakeCommunityRepository(loader: loader),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(addressControllerProvider.notifier);
    if (verified) {
      controller.acceptVerification(
        district: _district,
        proof: ResidencyVerificationProof(
          opaqueToken: 'fixture-token',
          verifiedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    } else {
      controller.continueReadOnly(district: _district);
    }

    final router = GoRouter(
      initialLocation: AppRoutes.community,
      routes: [
        GoRoute(
          path: AppRoutes.community,
          builder: (context, state) => const CommunityScreen(),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const Scaffold(body: Text('온보딩')),
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
    return container;
  }

  /// The summary card behind the sheet shows the same four axis names, so a
  /// bare text finder matches twice once the sheet is open.
  Finder inSheet(String label) => find.descendant(
    of: find.byType(ReviewComposeSheet),
    matching: find.text(label),
  );

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the hub', () {
    testWidgets('holds all three conversations under one district', (
      tester,
    ) async {
      await pumpCommunity(tester);

      expect(find.text('서울 마포구 을 커뮤니티'), findsOneWidget);
      for (final tab in ['주민 평가', '지역 채팅', '정책 토론']) {
        expect(find.text(tab), findsOneWidget);
      }
    });

    testWidgets('an unverified resident can still read every tab', (
      tester,
    ) async {
      await pumpCommunity(tester);

      expect(find.text('3.8'), findsOneWidget);

      await openTab(tester, '지역 채팅');
      expect(find.textContaining('판정문 읽어보신 분'), findsOneWidget);

      await openTab(tester, '정책 토론');
      expect(find.text('숲길 확장 번복 판정'), findsOneWidget);
    });

    // Threads open from bills and judgements, so no one owns the framing by
    // being first to post.
    testWidgets('says where its threads come from', (tester) async {
      await pumpCommunity(tester);
      await openTab(tester, '정책 토론');

      expect(find.textContaining('법안 발의로 자동 생성'), findsWidgets);
      expect(find.textContaining('누가 먼저 쓰느냐로 주제가 정해지지 않습니다'), findsOneWidget);
    });
  });

  group('writing a review', () {
    testWidgets('is blocked and explained for an unverified resident', (
      tester,
    ) async {
      await pumpCommunity(tester);

      await tester.tap(find.text('평가 작성'));
      await tester.pumpAndSettle();

      expect(find.text('주민 인증이 필요합니다'), findsOneWidget);
      expect(find.text('주민 평가 작성'), findsNothing);
    });

    testWidgets('opens the sheet for a verified resident', (tester) async {
      await pumpCommunity(tester, verified: true);

      await tester.tap(find.text('평가 작성'));
      await tester.pumpAndSettle();

      expect(find.text('주민 평가 작성'), findsOneWidget);
      for (final axis in ReviewDraft.axes) {
        expect(inSheet(axis), findsOneWidget);
      }
    });

    // Disabling without saying why leaves the author guessing which of the
    // two requirements they have missed.
    testWidgets('says what is still missing rather than only disabling', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await tester.tap(find.text('평가 작성'));
      await tester.pumpAndSettle();

      expect(find.text('네 항목 모두 별점을 매겨 주세요.'), findsOneWidget);
    });

    testWidgets('posts, and the summary moves with it', (tester) async {
      final container = await pumpCommunity(tester, verified: true);
      final before = await container.read(reviewBoardProvider.future);

      await tester.tap(find.text('평가 작성'));
      await tester.pumpAndSettle();

      for (final axis in ReviewDraft.axes) {
        await tester.tapAt(
          tester.getTopLeft(inSheet(axis)) + const Offset(180, 12),
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byType(TextField),
        '입주 공고와 착공 보도를 직접 확인했습니다.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('평가 올리기'));
      await tester.pumpAndSettle();

      final after = await container.read(reviewBoardProvider.future);
      expect(after.reviews.length, before.reviews.length + 1);
      expect(after.summary.respondents, before.summary.respondents + 1);
      expect(find.textContaining('입주 공고와 착공 보도'), findsOneWidget);
    });

    // Anonymous is the choice the app cannot undo on the author's behalf, so
    // it is the rest state rather than something they opt into.
    testWidgets('defaults to anonymous and says the choice is final', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await tester.tap(find.text('평가 작성'));
      await tester.pumpAndSettle();

      expect(find.textContaining('익명으로 작성 · 게시 후 변경할 수 없습니다'), findsOneWidget);
    });
  });

  group('the channel', () {
    testWidgets('will not take a message from an unverified resident', (
      tester,
    ) async {
      await pumpCommunity(tester);
      await openTab(tester, '지역 채팅');

      expect(find.text('주소 인증 주민만 보낼 수 있습니다'), findsOneWidget);
    });

    testWidgets('sends and shows the message', (tester) async {
      await pumpCommunity(tester, verified: true);
      await openTab(tester, '지역 채팅');

      await tester.enterText(find.byType(TextField), '회의록 링크 공유합니다.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('회의록 링크 공유합니다.'), findsOneWidget);
    });

    // Interception, not moderation: a message the author can still take back
    // is a different thing from one already delivered.
    testWidgets('holds a flagged message once and lets it through after', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await openTab(tester, '지역 채팅');

      await tester.enterText(find.byType(TextField), '저 사람 멍청한 소리만 합니다');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('혐오 표현으로 감지된'), findsOneWidget);
      expect(
        find.text('저 사람 멍청한 소리만 합니다'),
        findsOneWidget,
      ); // still in the field

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('혐오 표현으로 감지된'), findsNothing);
    });
  });

  group('the content guard', () {
    test('flags what it is meant to and leaves the rest alone', () {
      expect(ContentGuard.inspect('멍청한 소리'), ContentWarning.hate);
      expect(
        ContentGuard.inspect('이건 확실히 조작입니다'),
        ContentWarning.misinformation,
      );
      expect(ContentGuard.inspect('판정문 읽어보셨나요?'), isNull);
    });
  });
}
