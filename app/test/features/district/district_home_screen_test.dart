import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/district/application/district_providers.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';
import 'package:democracy/src/features/district/presentation/district_home_screen.dart';
import 'package:democracy/src/features/pledges/application/pledge_providers.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';
import 'package:democracy/src/features/shared/presentation/provenance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _district = DistrictRef(id: 'fixture-a', displayName: '가상 지역구');

const _source = {
  'sourceUrl': 'https://open.assembly.go.kr/fixture',
  'fetchedAt': '2026-07-30T09:00:00Z',
};

class FakeProfileRepository implements DistrictRepository {
  const FakeProfileRepository({this.failure, this.withRecord = true});

  final Object? failure;

  /// A district whose activity feed is not wired yet still has to render.
  final bool withRecord;

  @override
  Future<DistrictProfile> loadProfile(String districtId) async {
    if (failure != null) {
      throw failure!;
    }
    return DistrictProfile.fromJson({
      'district': {'id': districtId, 'displayName': _district.displayName},
      'source': _source,
      'incumbent': {
        'id': 'fixture-incumbent',
        'name': '가상 의원',
        'party': '가나당',
        'stats': [
          {
            'label': '출석률',
            'unit': '%',
            'value': {'value': 92, ..._source},
          },
        ],
        if (withRecord)
          'record': {
            'bills': {
              'source': _source,
              'items': [
                {
                  'id': 'fixture-bill-1',
                  'title': '가상 법안',
                  'stage': '소위 심사',
                  'stamp': '6월 3일',
                },
              ],
            },
            'attendance': {
              'unit': '%',
              'source': _source,
              'points': [
                {'label': '6월', 'value': 92},
                {'label': '7월', 'value': 95},
              ],
            },
            'votes': {
              'unit': '%',
              'source': _source,
              'points': [
                {'label': '6월', 'value': 87},
                {'label': '7월', 'value': 88},
              ],
            },
          },
      },
      'candidates': [
        {
          'id': 'fixture-c3',
          'name': '다후보',
          'party': '다라당',
          'stats': <Object?>[],
        },
        {
          'id': 'fixture-c1',
          'name': '가후보',
          'party': '나다당',
          'stats': <Object?>[],
        },
      ],
    });
  }
}

class FakeBoardRepository implements PledgeRepository {
  const FakeBoardRepository();

  @override
  Future<PledgeBoard> loadBoard(String districtId) async {
    return PledgeBoard.fromJson({
      'source': _source,
      'pledges': [
        {
          'id': 'fixture-pledge-1',
          'title': '가상 공약',
          'status': 'inProgress',
          'source': _source,
        },
      ],
    });
  }
}

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    DistrictRepository profileRepository = const FakeProfileRepository(),
  }) async {
    final container = ProviderContainer(
      overrides: [
        addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
        districtRepositoryProvider.overrideWithValue(profileRepository),
        pledgeRepositoryProvider.overrideWithValue(const FakeBoardRepository()),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: const DistrictHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the district and its read-only state', (tester) async {
    await pumpHome(tester);

    expect(find.text('가상 지역구'), findsOneWidget);
    expect(find.text('읽기 전용'), findsOneWidget);
  });

  testWidgets('every figure is shown with its source and as-of date', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('92%'), findsOneWidget);
    expect(
      find.textContaining('출처: open.assembly.go.kr'),
      findsWidgets,
      reason: 'A figure must never appear without its attribution.',
    );
    expect(find.textContaining('기준'), findsWidgets);
  });

  testWidgets('candidates are listed in name order with the rule on screen', (
    tester,
  ) async {
    await pumpHome(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where((text) => text.endsWith('후보'))
        .toList();

    expect(names.indexOf('가후보'), lessThan(names.indexOf('다후보')));
    expect(find.textContaining('가나다순'), findsOneWidget);
  });

  testWidgets('a pledge status is never colour alone', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining(PledgeStatus.inProgress.label), findsOneWidget);
    expect(find.textContaining(PledgeStatus.inProgress.glyph), findsOneWidget);
  });

  testWidgets('an unsourced payload is reported as such, not rendered', (
    tester,
  ) async {
    await pumpHome(
      tester,
      profileRepository: const FakeProfileRepository(
        failure: MissingSourceException(
          field: '출석률',
          reason: 'sourceUrl is absent or empty.',
        ),
      ),
    );

    // The profile feeds both the incumbent and the candidate sections, so a
    // rejected payload surfaces in each of them.
    expect(find.textContaining('출처가 확인되지 않아'), findsWidgets);
    expect(find.text('92%'), findsNothing);
  });

  group('the record tabs', () {
    testWidgets('open the bill, attendance and vote panes', (tester) async {
      await pumpHome(tester);

      for (final tab in ['법안', '출석', '표결']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      expect(find.text('월별 표결 참여율'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
    });

    // A sparkline says nothing to a screen reader, so the shape is spelled
    // out beside it rather than left as decoration.
    testWidgets('describe the sparkline for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);

      await tester.tap(find.text('출석'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'최저 92%, 최고 95%, 최근 95%')),
        findsOneWidget,
      );
      handle.dispose();
    });

    // A district whose activity feed is not wired must still render.
    testWidgets('say so when there is no record behind them', (tester) async {
      await pumpHome(
        tester,
        profileRepository: const FakeProfileRepository(withRecord: false),
      );

      await tester.tap(find.text('법안'));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 연결되지 않았습니다'), findsOneWidget);
    });
  });

  group('the source badge', () {
    // An attribution the reader cannot follow is an assertion. N-4 is about
    // being checkable, not about printing a hostname.
    testWidgets('opens the original it names', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: Scaffold(
            body: SourceBadge(
              source: SourceMetadata.fromJson(_source, field: 'test'),
              onOpen: (url) async => opened.add(url),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SourceBadge));
      await tester.pump();

      expect(opened, [Uri.parse('https://open.assembly.go.kr/fixture')]);
    });
  });
}
