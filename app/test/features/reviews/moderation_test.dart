import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/account/presentation/blocked_authors_screen.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/reviews/application/moderation_providers.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/reviews/data/remote_moderation_repository.dart';
import 'package:democracy/src/features/reviews/domain/channel_event.dart';
import 'package:democracy/src/features/reviews/domain/moderation.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(
    account: Account(
      userId: 'reader',
      provider: SignInProvider.email,
      handle: '솔숲 27',
    ),
  );
}

void main() {
  group('the channel log', () {
    ChatMessage msg(String id, {bool hidden = false, bool mine = false}) =>
        ChatMessage(
          id: id,
          author: '익명 주민',
          body: hidden ? '신고로 가려진 글입니다.' : '본문',
          verifiedResident: true,
          mine: mine,
          hidden: hidden,
        );

    test('a hidden broadcast replaces the message in place', () {
      final log = ChannelLog.read([msg('a'), msg('b', mine: true)]);
      final event = ChannelEvent.fromBroadcast('hidden', {
        'id': 'b',
        'author': '익명 주민',
        'body': '신고로 가려진 글입니다.',
        'hidden': true,
      });
      expect(event, isA<MessageChanged>());

      final next = log.apply(event!);
      expect(next.messages.map((m) => m.id), ['a', 'b']);
      expect(next.messages[1].hidden, isTrue);
      // Still the reader's own, though the broadcast cannot know it.
      expect(next.messages[1].mine, isTrue);
      expect(next.showsSameAs(log), isFalse);
    });

    test('a hidden broadcast for a message never read changes nothing', () {
      final log = ChannelLog.read([msg('a')]);
      expect(log.apply(MessageChanged(msg('z', hidden: true))), same(log));
    });
  });

  group('report and hide', () {
    Future<(ProviderContainer, FakeModerationRepository)> pump(
      WidgetTester tester, {
      bool signedIn = true,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final loader = fixtureLoaderFromDisk();
      final moderation = FakeModerationRepository();
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
          moderationRepositoryProvider.overrideWithValue(moderation),
          if (signedIn) authControllerProvider.overrideWith(_SignedIn.new),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(addressControllerProvider.notifier)
          .continueReadOnly(district: _district);

      final router = GoRouter(
        initialLocation: AppRoutes.community,
        routes: [
          GoRoute(
            path: AppRoutes.community,
            builder: (context, state) => const CommunityScreen(),
          ),
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) => const Scaffold(body: Text('로그인 화면')),
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
      return (container, moderation);
    }

    Future<void> openMenu(WidgetTester tester, String id) async {
      final menu = find.byKey(ValueKey('post-menu-$id'));
      await tester.ensureVisible(menu);
      await tester.tap(
        find.descendant(of: menu, matching: find.byType(IconButton)).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every other resident\'s review carries the menu', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.byKey(const ValueKey('post-menu-fixture-review-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('post-menu-fixture-review-2')),
        findsOneWidget,
      );
    });

    testWidgets('a report goes out with the chosen reason', (tester) async {
      final (_, moderation) = await pump(tester);

      await openMenu(tester, 'fixture-review-1');
      await tester.tap(find.text('신고하기').last);
      await tester.pumpAndSettle();

      // Nothing is sent until a reason is picked.
      expect(find.text('개인정보 노출'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-privacy')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '신고하기').last);
      await tester.pumpAndSettle();

      expect(moderation.reports, [
        (PostKind.review, 'fixture-review-1', ReportReason.privacy),
      ]);
      expect(find.text('신고했습니다. 이 글은 지금부터 가려집니다.'), findsOneWidget);
    });

    testWidgets('signed out, the reader is offered sign-in first', (
      tester,
    ) async {
      final (_, moderation) = await pump(tester, signedIn: false);

      await openMenu(tester, 'fixture-review-1');
      await tester.tap(find.text('신고하기').last);
      await tester.pumpAndSettle();

      expect(find.text('로그인이 필요합니다'), findsOneWidget);
      expect(moderation.reports, isEmpty);
      await tester.tap(find.text('로그인'));
      await tester.pumpAndSettle();
      expect(find.text('로그인 화면'), findsOneWidget);
    });

    testWidgets('hiding an author asks first, then lists them', (tester) async {
      final (container, moderation) = await pump(tester);

      await openMenu(tester, 'fixture-review-2');
      await tester.tap(find.text('이 주민 글 숨기기'));
      await tester.pumpAndSettle();
      expect(find.text('이 주민의 글을 숨길까요?'), findsOneWidget);
      await tester.tap(find.text('숨기기'));
      await tester.pumpAndSettle();

      expect(await moderation.loadBlocks(), hasLength(1));
      // The list is read again, and with it the tag for the live channel.
      await container.read(blocksProvider.future);
      expect(container.read(blockedTagsProvider), {'tag-fixture-review-2'});
      expect(find.text('이 주민의 글을 숨겼습니다.'), findsOneWidget);
    });
  });

  testWidgets('숨긴 주민 lists the blocks and shows one again', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final moderation = FakeModerationRepository();
    await moderation.block(PostKind.message, 'm1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moderationRepositoryProvider.overrideWithValue(moderation),
          authControllerProvider.overrideWith(_SignedIn.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: const BlockedAuthorsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('익명 주민'), findsOneWidget);

    await tester.tap(find.text('다시 보기'));
    await tester.pumpAndSettle();
    expect(find.text('숨긴 주민이 없습니다.'), findsOneWidget);
  });
}
