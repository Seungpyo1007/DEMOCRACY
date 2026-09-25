import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/app_controls.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:democracy/src/features/reviews/presentation/review_compose_screen.dart';
import 'package:flutter/cupertino.dart';
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
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loader = fixtureLoaderFromDisk();
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
          path: AppRoutes.reviewCompose,
          builder: (context, state) => const ReviewComposeScreen(),
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
          theme: AppTheme.light(platform),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The hub stays mounted under the pushed page and its summary shows the
  /// same four axis names, so finders are scoped to the page.
  Finder inPage(String label) => find.descendant(
    of: find.byType(ReviewComposeScreen),
    matching: find.text(label),
  );

  /// The missing-item note sits at the foot of the page, below the fold on
  /// a phone, so it is scrolled to before it is looked for.
  Future<void> scrollToFoot(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ReviewComposeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  Future<void> openCompose(WidgetTester tester) async {
    await tester.tap(find.text('평가 작성'));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the hub', () {
    testWidgets('holds all three conversations under one district', (
      tester,
    ) async {
      await pumpCommunity(tester);

      // Material's large top app bar sets the title twice -- expanded and
      // collapsed -- so the title is the bar's, not a hand-drawn header.
      expect(
        find.descendant(
          of: find.byType(SliverAppBar),
          matching: find.text('커뮤니티'),
        ),
        findsWidgets,
      );
      // Whose seat, and where: the kicker names both.
      expect(find.text('가상 의원 · 서울 마포구 을'), findsOneWidget);
      // Android's own primary tabs, not a drawn strip.
      for (final tab in ['주민 평가', '지역 채팅', '정책 토론']) {
        expect(
          find.descendant(of: find.byType(TabBar), matching: find.text(tab)),
          findsOneWidget,
        );
      }
    });

    testWidgets('on iOS, sets the title on the page over segmented tabs', (
      tester,
    ) async {
      await pumpCommunity(tester, platform: TargetPlatform.iOS);

      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.text('커뮤니티'), findsOneWidget);
      expect(find.text('가상 의원 · 서울 마포구 을'), findsOneWidget);
      for (final tab in ['주민 평가', '지역 채팅', '정책 토론']) {
        expect(
          find.descendant(
            of: find.byType(AppSegmentedControl),
            matching: find.text(tab),
          ),
          findsOneWidget,
        );
      }

      await openTab(tester, '정책 토론');
      expect(find.text('숲길 확장 번복 판정'), findsOneWidget);
    });

    testWidgets('an unverified resident can still read every tab', (
      tester,
    ) async {
      await pumpCommunity(tester);

      expect(find.text('3.8', findRichText: true), findsOneWidget);
      expect(find.text('주민 412명 평가'), findsOneWidget);

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

      // Android's write action is Material 3's own extended FAB, alone: the
      // anonymous choice is made on the page, not on the hub.
      expect(
        find.widgetWithText(FloatingActionButton, '평가 작성'),
        findsOneWidget,
      );
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('익명으로 작성'), findsNothing);
      expect(find.byType(AppSwitch), findsNothing);

      await openCompose(tester);

      expect(find.text('로그인하고 계속'), findsOneWidget);
      expect(find.byType(ReviewComposeScreen), findsNothing);
    });

    testWidgets('opens its own page for a verified resident', (tester) async {
      await pumpCommunity(tester, verified: true);

      await openCompose(tester);

      // A pushed page under Material's large top app bar, with a way back --
      // not a sheet over the hub.
      expect(find.byType(ReviewComposeScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SliverAppBar),
          matching: find.text('주민 평가 작성'),
        ),
        findsWidgets,
      );
      expect(inPage('가상 의원 · 서울 마포구 을'), findsOneWidget);
      expect(find.byTooltip('뒤로'), findsOneWidget);
      for (final axis in ReviewDraft.axes) {
        expect(inPage(axis), findsOneWidget);
      }
    });

    // Disabling without saying why leaves the author guessing which of the
    // two requirements they have missed.
    testWidgets('says what is still missing rather than only disabling', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await openCompose(tester);

      await scrollToFoot(tester, find.text('네 항목 모두 별점을 매겨 주세요.'));
      expect(find.text('네 항목 모두 별점을 매겨 주세요.'), findsOneWidget);
    });

    testWidgets('posts, and the summary moves with it', (tester) async {
      final container = await pumpCommunity(tester, verified: true);
      final before = await container.read(reviewBoardProvider.future);

      await openCompose(tester);

      for (final axis in ReviewDraft.axes) {
        await tester.tap(find.byKey(ReviewComposeScreen.starKey(axis, 4)));
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
      // Back on the hub, which says so, with the review among the others.
      expect(find.byType(ReviewComposeScreen), findsNothing);
      expect(find.text('평가를 올렸습니다.'), findsOneWidget);
      expect(find.textContaining('입주 공고와 착공 보도'), findsOneWidget);
    });

    // Anonymous is the choice the app cannot undo on the author's behalf, so
    // it is the rest state rather than something they opt into.
    testWidgets('defaults to anonymous and says the choice is final', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await openCompose(tester);

      expect(inPage('익명으로 작성'), findsOneWidget);
      expect(inPage('게시 후 변경할 수 없습니다'), findsOneWidget);
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isTrue);
    });

    testWidgets('lets the author switch anonymity off, warning either way', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await openCompose(tester);

      await tester.tap(inPage('익명으로 작성'));
      await tester.pumpAndSettle();

      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isFalse);
      // Switched off, the warning is still there: it is the choice, not the
      // default, that cannot be taken back.
      expect(inPage('게시 후 변경할 수 없습니다'), findsOneWidget);
    });

    testWidgets('leaves by the back button without posting', (tester) async {
      final container = await pumpCommunity(tester, verified: true);
      final before = await container.read(reviewBoardProvider.future);
      await openCompose(tester);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewComposeScreen), findsNothing);
      expect(find.text('평가를 올렸습니다.'), findsNothing);
      final after = await container.read(reviewBoardProvider.future);
      expect(after.reviews.length, before.reviews.length);
    });

    testWidgets('says what is missing next once the stars are in', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true);
      await openCompose(tester);

      for (final axis in ReviewDraft.axes) {
        await tester.tap(find.byKey(ReviewComposeScreen.starKey(axis, 2)));
      }
      await tester.pumpAndSettle();

      final next = find.text('본문을 ${ReviewDraft.minBodyLength}자 이상 적어 주세요.');
      await scrollToFoot(tester, next);
      expect(find.text('네 항목 모두 별점을 매겨 주세요.'), findsNothing);
      expect(
        find.text('본문을 ${ReviewDraft.minBodyLength}자 이상 적어 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('every star is a target of at least 44', (tester) async {
      await pumpCommunity(tester, verified: true);
      await openCompose(tester);

      for (final axis in ReviewDraft.axes) {
        for (var i = 1; i <= ReviewDraft.maxScore; i++) {
          final size = tester.getSize(
            find.byKey(ReviewComposeScreen.starKey(axis, i)),
          );
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
      }
    });

    testWidgets('holds a flagged review once before posting it', (
      tester,
    ) async {
      final container = await pumpCommunity(tester, verified: true);
      final before = await container.read(reviewBoardProvider.future);

      await openCompose(tester);
      for (final axis in ReviewDraft.axes) {
        await tester.tap(find.byKey(ReviewComposeScreen.starKey(axis, 3)));
      }
      await tester.enterText(find.byType(TextField), '이건 확실히 조작입니다 여러분');
      await tester.pumpAndSettle();

      await tester.tap(find.text('평가 올리기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('사실과 다를 수 있는'), findsOneWidget);
      expect(find.byType(ReviewComposeScreen), findsOneWidget);

      await tester.tap(find.text('평가 올리기'));
      await tester.pumpAndSettle();
      final after = await container.read(reviewBoardProvider.future);
      expect(after.reviews.length, before.reviews.length + 1);
    });

    testWidgets('on iOS, floats a compact action with the same gate', (
      tester,
    ) async {
      await pumpCommunity(tester, platform: TargetPlatform.iOS);

      expect(find.widgetWithText(AppPrimaryButton, '평가 작성'), findsOneWidget);
      // No anonymous toggle on the hub; the choice is made on the page.
      expect(find.text('✓ 익명'), findsNothing);
      expect(find.text('익명으로 작성'), findsNothing);
      expect(find.byType(AppSwitch), findsNothing);

      await openCompose(tester);

      expect(find.text('로그인하고 계속'), findsOneWidget);
      expect(find.byType(ReviewComposeScreen), findsNothing);
    });

    testWidgets('on iOS, writes on a page with a Cupertino field', (
      tester,
    ) async {
      final container = await pumpCommunity(
        tester,
        verified: true,
        platform: TargetPlatform.iOS,
      );
      final before = await container.read(reviewBoardProvider.future);
      await openCompose(tester);

      expect(find.byType(SliverAppBar), findsNothing);
      expect(inPage('주민 평가 작성'), findsOneWidget);
      expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isTrue);
      expect(inPage('게시 후 변경할 수 없습니다'), findsOneWidget);

      for (final axis in ReviewDraft.axes) {
        await tester.tap(find.byKey(ReviewComposeScreen.starKey(axis, 5)));
      }
      await tester.enterText(
        find.byType(CupertinoTextField),
        '구청 회의록과 예산서를 대조해 보았습니다.',
      );
      await tester.pumpAndSettle();

      // The pinned button leaves the page's last line reachable above it.
      final button = tester.getRect(
        find.widgetWithText(AppPrimaryButton, '평가 올리기'),
      );
      expect(button.bottom, lessThanOrEqualTo(844));

      await tester.tap(find.text('평가 올리기'));
      await tester.pumpAndSettle();

      final after = await container.read(reviewBoardProvider.future);
      expect(after.reviews.length, before.reviews.length + 1);
      expect(find.byType(ReviewComposeScreen), findsNothing);
      expect(find.text('평가를 올렸습니다.'), findsOneWidget);
    });
  });

  group('the review board', () {
    testWidgets('keeps the rule about who may write in view', (tester) async {
      await pumpCommunity(tester);

      expect(
        find.textContaining('주소 인증 주민만 작성 가능 · 조작 방지 알고리즘 · 혐오·허위정보 자동 필터링'),
        findsOneWidget,
      );
    });

    testWidgets('marks verified reviews and reads each rating as a number', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCommunity(tester);

      expect(find.text('✓ 인증'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('별점 [1-5]점')), findsWidgets);
      handle.dispose();
    });
  });

  group('the channel', () {
    testWidgets('will not take a message from an unverified resident', (
      tester,
    ) async {
      await pumpCommunity(tester);
      await openTab(tester, '지역 채팅');

      expect(find.text('주소 인증 주민만 보낼 수 있습니다'), findsOneWidget);

      // The send button explains the gate rather than sitting dead.
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('로그인하고 계속'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
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

  group('the channel on iOS', () {
    testWidgets('takes a Cupertino field and a glass send button', (
      tester,
    ) async {
      await pumpCommunity(tester, verified: true, platform: TargetPlatform.iOS);
      await openTab(tester, '지역 채팅');

      expect(find.byType(CupertinoTextField), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), '회의록 링크 공유합니다.');
      await tester.tap(find.bySemanticsLabel('보내기'));
      await tester.pumpAndSettle();

      expect(find.text('회의록 링크 공유합니다.'), findsOneWidget);
    });

    testWidgets('still gates sending for an unverified resident', (
      tester,
    ) async {
      await pumpCommunity(tester, platform: TargetPlatform.iOS);
      await openTab(tester, '지역 채팅');

      expect(find.text('주소 인증 주민만 보낼 수 있습니다'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('보내기'));
      await tester.pumpAndSettle();
      expect(find.text('로그인하고 계속'), findsOneWidget);
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
