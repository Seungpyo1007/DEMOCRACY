import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/history/application/history_providers.dart';
import 'package:democracy/src/features/history/data/fake_history_repository.dart';
import 'package:democracy/src/features/history/domain/history_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixture_bundle.dart';

const _fixturePath = 'assets/fixtures/history_fixture-seoul-mapo-b.json';

/// A fresh, mutable copy of the shipped fixture for each test to break.
Map<String, Object?> _fixture() =>
    json.decode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _block(Map<String, Object?> payload, String key) =>
    payload[key]! as Map<String, Object?>;

void main() {
  group('HistoryRecord.fromJson', () {
    test('reads the three parts of the shipped fixture', () {
      final record = HistoryRecord.fromJson(_fixture());

      expect(record.district.displayName, '서울 마포구 을');
      expect(record.region.events.map((e) => e.title), [
        '마포구 설치',
        '선거구 획정으로 마포구 갑·을 분리',
        '서울월드컵경기장 개장',
        '경의선 숲길 전 구간 개통',
      ]);
      expect(record.elections.rows.map((r) => r.term), [20, 21, 22, 23]);
      expect(record.elections.decided.map((r) => r.share), [44.1, 46.8, 45.2]);
      expect(record.legislator.name, '가상 의원');
      expect(record.legislator.events, hasLength(5));
    });

    test('keeps an unknown year as null rather than guessing one', () {
      final record = HistoryRecord.fromJson(_fixture());

      expect(record.region.events.first.year, 1944);
      expect(record.region.events[1].year, isNull);
    });

    test('rejects a year that is neither a year nor null', () {
      final payload = _fixture();
      final events = _block(payload, 'region')['events']! as List;
      (events.first as Map<String, Object?>)['year'] = '1944년쯤';

      expect(
        () => HistoryRecord.fromJson(payload),
        throwsA(isA<MissingSourceException>()),
      );
    });

    for (final part in ['region', 'elections', 'legislator']) {
      test('refuses the $part part without a source', () {
        final payload = _fixture();
        _block(payload, part).remove('source');

        expect(
          () => HistoryRecord.fromJson(payload),
          throwsA(
            isA<MissingSourceException>().having((e) => e.field, 'field', part),
          ),
        );
      });
    }

    test('refuses a decided election without a share', () {
      final payload = _fixture();
      final rows = _block(payload, 'elections')['rows']! as List;
      (rows.first as Map<String, Object?>).remove('share');

      expect(
        () => HistoryRecord.fromJson(payload),
        throwsA(isA<MissingSourceException>()),
      );
    });

    test('an ongoing election needs no winner', () {
      final record = HistoryRecord.fromJson(_fixture());
      final current = record.elections.rows.last;

      expect(current.ongoing, isTrue);
      expect(current.termLabel, '제23대');
      expect(current.winner, isNull);
      expect(record.elections.decided, isNot(contains(current)));
    });
  });

  group('first win', () {
    test('is the earliest election the incumbent won', () {
      final record = HistoryRecord.fromJson(_fixture());

      expect(record.incumbentFirstWinYear, 2020);
    });

    test('follows the rows, not their order in the payload', () {
      final payload = _fixture();
      final rows = _block(payload, 'elections')['rows']! as List;
      // The 2020 seat goes to someone else and the rows arrive shuffled.
      (rows[1] as Map<String, Object?>)['winner'] = {
        'id': 'fixture-other',
        'name': '가상 인물 마',
        'party': '다라당',
      };
      final shuffled = rows.reversed.toList();
      rows
        ..clear()
        ..addAll(shuffled);

      final record = HistoryRecord.fromJson(payload);

      expect(record.incumbentFirstWinYear, 2024);
    });

    test('is null for someone who has never won here', () {
      final record = HistoryRecord.fromJson(_fixture());

      expect(record.elections.firstWinYear('fixture-nobody'), isNull);
    });
  });

  group('historyRecordProvider', () {
    ProviderContainer containerWith({DistrictRef? district}) {
      final container = ProviderContainer(
        overrides: [
          addressStoreProvider.overrideWithValue(InMemoryAddressStore()),
          historyRepositoryProvider.overrideWithValue(
            FakeHistoryRepository(loader: fixtureLoaderFromDisk()),
          ),
        ],
      );
      addTearDown(container.dispose);
      if (district != null) {
        container
            .read(addressControllerProvider.notifier)
            .continueReadOnly(district: district);
      }
      return container;
    }

    test('loads the history of the current district', () async {
      final container = containerWith(
        district: const DistrictRef(
          id: 'fixture-seoul-mapo-b',
          displayName: '서울 마포구 을',
        ),
      );

      final record = await container.read(historyRecordProvider.future);

      expect(record.district.id, 'fixture-seoul-mapo-b');
    });

    test('fails without a district', () async {
      final container = containerWith();

      await expectLater(
        container.read(historyRecordProvider.future),
        throwsA(isA<StateError>()),
      );
    });
  });
}
