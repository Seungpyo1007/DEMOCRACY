import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_providers.dart';
import 'package:democracy/src/core/on_device_ai/on_device_runner.dart';
import 'package:democracy/src/core/time/clock.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/ai_match/application/direction_providers.dart';
import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/ai_match/data/on_device/on_device_direction_source.dart';
import 'package:democracy/src/features/ai_match/data/on_device/on_device_match_repository.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_direction_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_disclosure.dart';
import 'package:democracy/src/features/ai_match/presentation/ai_match_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/algorithm_log_screen.dart';
import 'package:democracy/src/features/ai_match/presentation/on_device_notice.dart';
import 'package:democracy/src/features/district/data/fake_district_repository.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/pledges/data/fake_pledge_repository.dart';
import 'package:democracy/src/features/reviews/data/fake_review_repository.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_on_device_model.dart';
import '../../support/fixture_bundle.dart';

const _district = DistrictRef(
  id: 'fixture-seoul-mapo-b',
  displayName: '서울 마포구 을',
);

/// The live wiring of the AI tab, with the device's model replaced by a
/// script: the repositories, validation and screens are the real ones.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required ScriptedOnDeviceModel model,
  required String route,
  Set<String> tags = const {'세금', '청년', '자영업'},
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final loader = fixtureLoaderFromDisk();
  final runner = OnDeviceRunner(
    model: model,
    cache: InMemoryOnDeviceResultCache(),
    clock: FixedClock(KstInstant.seoul(2026, 7, 30, 12)),
  );
  final districts = FakeDistrictRepository(loader: loader);
  final pledges = FakePledgeRepository(loader: loader);
  final bills = FixtureMemberBillsRepository(loader);
  final container = ProviderContainer(
    overrides: [
      addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
      onDeviceModelProvider.overrideWithValue(model),
      matchSubjectProvider.overrideWithValue(MatchSubject.incumbent),
      matchRepositoryProvider.overrideWithValue(
        OnDeviceMatchRepository(
          runner: runner,
          districts: districts,
          pledges: pledges,
          bills: bills,
        ),
      ),
      // The server's trend only, as a live build gets it.
      directionRepositoryProvider.overrideWithValue(const _TrendOnly()),
      directionAiSourceProvider.overrideWithValue(
        OnDeviceDirectionSource(
          runner: runner,
          districts: districts,
          pledges: pledges,
          bills: bills,
          community: FakeCommunityRepository(loader: loader),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  container
      .read(addressControllerProvider.notifier)
      .continueReadOnly(district: _district);
  container.read(residentProfileProvider.notifier).setTags(tags);

  final router = GoRouter(
    initialLocation: route,
    routes: [
      GoRoute(
        path: AppRoutes.aiMatch,
        builder: (context, state) => const AiMatchScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.algorithmLogSegment,
            builder: (context, state) => const AlgorithmLogScreen(),
          ),
          GoRoute(
            path: AppRoutes.aiDirectionSegment,
            builder: (context, state) => const AiDirectionScreen(),
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
  return container;
}

Object? _answer(OnDeviceRequest request) {
  final keys = RegExp(
    r'^([PIB]\d+) ',
    multiLine: true,
  ).allMatches(request.prompt).map((m) => m[1]!).toList();
  return switch (request.task) {
    OnDeviceTask.match => {
      'axes': [
        {
          'label': '세금',
          'score': 72,
          'reasons': [
            {'id': 'P2', 'text': '세제 관련 공약이 있습니다.'},
            {'id': 'P404', 'text': '없는 공약을 인용한 문장'},
          ],
        },
        {
          'label': '청년',
          'score': 40,
          'reasons': [
            {'id': 'B1', 'text': '임대차 제도를 다루는 법안입니다.'},
          ],
        },
      ],
    },
    OnDeviceTask.stances => {
      'items': [
        for (final key in keys) {'id': key, 'x': 1, 'y': 0},
      ],
    },
    OnDeviceTask.issues => {
      'items': [
        for (final key in keys) {'id': key, 'label': '교통'},
      ],
    },
  };
}

void main() {
  group('the match on a device without the model', () {
    for (final (reason, label) in [
      (ModelUnavailableReason.deviceNotEligible, '지원 기기 아님'),
      (
        ModelUnavailableReason.appleIntelligenceNotEnabled,
        'Apple Intelligence 꺼짐',
      ),
      (ModelUnavailableReason.modelNotReady, '모델 준비 중'),
    ]) {
      testWidgets('says why (${reason.name}) and draws no score', (
        tester,
      ) async {
        final model = ScriptedOnDeviceModel(
          answer: _answer,
          status: ModelUnavailable(reason),
        );
        await _pump(tester, model: model, route: AppRoutes.aiMatch);

        expect(find.text(onDeviceUnavailableTitle), findsOneWidget);
        expect(find.textContaining(label, findRichText: true), findsOneWidget);
        // No figure, no label, no sample.
        expect(find.byType(AiReferenceLabel), findsNothing);
        expect(
          find.textContaining(RegExp(r'^\d+점$'), findRichText: true),
          findsNothing,
        );
        expect(find.textContaining('가상 후보'), findsNothing);
        expect(model.requests, isEmpty);
      });
    }

    testWidgets('offers the download where the platform allows it', (
      tester,
    ) async {
      final model = ScriptedOnDeviceModel(
        answer: _answer,
        status: const ModelUnavailable(
          ModelUnavailableReason.modelDownloadable,
        ),
      );
      await _pump(tester, model: model, route: AppRoutes.aiMatch);

      await tester.tap(find.text('모델 내려받기'));
      await tester.pumpAndSettle();
      expect(model.prepared, 1);
    });
  });

  group('the match on a device with the model', () {
    testWidgets(
      'titles it as the member, labels the score, stamps the device',
      (tester) async {
        final model = ScriptedOnDeviceModel(answer: _answer);
        await _pump(tester, model: model, route: AppRoutes.aiMatch);

        expect(find.text('현 의원 공약과 내 관심사'), findsOneWidget);
        expect(find.text('나에게 유리한 후보는?'), findsNothing);
        expect(find.textContaining('이 기기에서 생성'), findsOneWidget);
        // The mean of 72 and 40.
        expect(find.text('56점', findRichText: true), findsOneWidget);
        expect(find.byType(AiReferenceLabel), findsWidgets);
        expect(find.text('관심사 바꾸기'), findsOneWidget);
      },
    );

    testWidgets('shows only the reasons whose citation checked out', (
      tester,
    ) async {
      final model = ScriptedOnDeviceModel(answer: _answer);
      await _pump(tester, model: model, route: AppRoutes.aiMatch);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('점수 근거'));
      await tester.pumpAndSettle();

      expect(find.text('세제 관련 공약이 있습니다.'), findsOneWidget);
      expect(find.text('임대차 제도를 다루는 법안입니다.'), findsOneWidget);
      expect(find.text('없는 공약을 인용한 문장'), findsNothing);
      expect(find.byType(SourceBadge), findsNWidgets(2));
    });

    testWidgets('with no interest picked, asks for one', (tester) async {
      final model = ScriptedOnDeviceModel(answer: _answer);
      await _pump(
        tester,
        model: model,
        route: AppRoutes.aiMatch,
        tags: const {'자영업'},
      );

      expect(find.text('관심 분야 고르기'), findsOneWidget);
      expect(model.requests, isEmpty);

      await tester.tap(find.text('관심 분야 고르기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('복지'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();

      // One run -- and a failed one (the script answers 세금·청년, not 복지)
      // is not retried behind the reader's back.
      expect(model.requests, hasLength(1));
      expect(model.requests.single.prompt, contains('관심 분야: 복지'));
    });
  });

  group('the direction view', () {
    testWidgets('without the model: the trend draws, 01 and 03 say why', (
      tester,
    ) async {
      final model = ScriptedOnDeviceModel(
        answer: _answer,
        status: const ModelUnavailable(
          ModelUnavailableReason.appleIntelligenceNotEnabled,
        ),
      );
      await _pump(tester, model: model, route: AppRoutes.aiDirection);

      expect(find.text('01 현 의원 공약 성향', findRichText: true), findsOneWidget);
      expect(find.text(onDeviceUnavailableTitle), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('03 지역 쟁점 흐름', findRichText: true),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(onDeviceUnavailableTitle), findsWidgets);
      // The count is not AI and is not hidden with it.
      expect(find.text(trendBasis), findsOneWidget);
      expect(find.byType(AiReferenceLabel), findsNothing);
    });

    testWidgets('with the model: both blocks drawn, labelled and stamped', (
      tester,
    ) async {
      final model = ScriptedOnDeviceModel(answer: _answer);
      await _pump(tester, model: model, route: AppRoutes.aiDirection);

      expect(find.text('01 현 의원 공약 성향', findRichText: true), findsOneWidget);
      expect(find.textContaining('기기 내 AI 분류'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('대표발의 법안·토론 제목 기준 · 기기 내 AI 분류'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('이 기기에서 생성'), findsWidgets);
      expect(find.byType(AiReferenceLabel), findsNWidgets(2));
      expect(find.text('교통'), findsOneWidget);
    });
  });
}

class _TrendOnly implements DirectionRepository {
  const _TrendOnly();

  @override
  Future<DirectionReport> loadReport(String districtId) async {
    final full = await const _Fixture().load();
    // What the BFF sends: the trend, and null for the model-made blocks.
    return DirectionReport(
      stances: null,
      trend: full.trend,
      issues: null,
      generatedAt: full.generatedAt,
    );
  }
}

class _Fixture {
  const _Fixture();

  Future<DirectionReport> load() async => DirectionReport.fromJson(
    await fixtureLoaderFromDisk().load('ai_direction_fixture-seoul-mapo-b'),
  );
}
