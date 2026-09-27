import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/app/live_data.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/auth/address_store.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/ai_match/data/remote_direction_repository.dart';
import 'package:democracy/src/features/district/data/remote_district_repository.dart';
import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:democracy/src/features/history/data/remote_history_repository.dart';
import 'package:democracy/src/features/onboarding/data/remote_address_repositories.dart';
import 'package:democracy/src/features/onboarding/domain/address_search.dart';
import 'package:democracy/src/features/pledges/data/remote_pledge_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import '../../support/fake_bff.dart';

/// The fixtures are the BFF contract: the server is written to send exactly
/// these shapes inside the envelope, so every one of them must parse through
/// the remote repositories as it does through the fakes.
Map<String, Object?> fixture(String name) {
  final decoded =
      json.decode(File('assets/fixtures/$name.json').readAsStringSync())
          as Map<String, Object?>;
  return decoded..remove('_note');
}

class _Positions implements PositionSource {
  _Positions({
    this.enabled = true,
    this.initial = LocationPermission.whileInUse,
    this.afterRequest = LocationPermission.whileInUse,
  });

  final bool enabled;
  final LocationPermission initial;
  final LocationPermission afterRequest;

  @override
  Future<LocationPermission> checkPermission() async => initial;

  @override
  Future<LocationPermission> requestPermission() async => afterRequest;

  @override
  Future<bool> isServiceEnabled() async => enabled;

  @override
  Future<({double latitude, double longitude})> current() async =>
      (latitude: 37.5563, longitude: 126.9220);
}

void main() {
  const id = 'nec-2110501';

  test('the district fixture is a valid profile response', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/districts/$id/profile': (
          status: 200,
          body: envelope(fixture('district_fixture-seoul-mapo-b')),
        ),
      }),
    );

    final profile = await RemoteDistrictRepository(client).loadProfile(id);

    expect(profile.district.displayName, '서울 마포구 을');
    expect(profile.incumbent.record, isNotNull);
  });

  test('the history fixture is a valid history response', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/districts/$id/history': (
          status: 200,
          body: envelope(fixture('history_fixture-seoul-mapo-b')),
        ),
      }),
    );

    final history = await RemoteHistoryRepository(client).loadHistory(id);

    expect(history.elections.rows, isNotEmpty);
  });

  test('the pledge fixture is a valid pledge response', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/districts/$id/pledges': (
          status: 200,
          body: envelope(fixture('pledges_fixture-seoul-mapo-b')),
        ),
      }),
    );

    final board = await RemotePledgeRepository(client).loadBoard(id);

    expect(board.pledges, isNotEmpty);
  });

  test('a district without curated pledges is not available', () async {
    final client = fakeBffClient(
      FakeBffAdapter({
        '/districts/$id/pledges': (
          status: 404,
          body: errorEnvelope('not_curated'),
        ),
      }),
    );

    await expectLater(
      RemotePledgeRepository(client).loadBoard(id),
      throwsA(isA<NotAvailableException>()),
    );
  });

  group('direction', () {
    test('the fixture is a valid direction response', () async {
      final client = fakeBffClient(
        FakeBffAdapter({
          '/districts/$id/direction': (
            status: 200,
            body: envelope(fixture('ai_direction_fixture-seoul-mapo-b')),
          ),
        }),
      );

      final report = await RemoteDirectionRepository(client).loadReport(id);

      expect(report.trend, isNotNull);
    });

    test('the live shape: a trend, and the model blocks null', () async {
      final trend =
          fixture('ai_direction_fixture-seoul-mapo-b')['trend']
              as Map<String, Object?>;
      final adapter = FakeBffAdapter({
        '/districts/$id/direction': (
          status: 200,
          body: envelope({
            'district': {'id': id, 'displayName': '서울 마포구 을'},
            'trend': trend,
            'stances': null,
            'issues': null,
          }),
        ),
      });

      final report = await RemoteDirectionRepository(
        fakeBffClient(adapter),
      ).loadReport(id);

      expect(report.trend!.billCount, 31);
      expect(report.stances, isNull);
      expect(report.issues, isNull);
      expect(adapter.requests.single.path, '/districts/$id/direction');
    });

    test('a district with no incumbent is not available', () async {
      final client = fakeBffClient(
        FakeBffAdapter({
          '/districts/$id/direction': (
            status: 404,
            body: errorEnvelope('not_found'),
          ),
        }),
      );

      await expectLater(
        RemoteDirectionRepository(client).loadReport(id),
        throwsA(isA<NotAvailableException>()),
      );
    });

    test('a trend without a source is refused', () async {
      final trend = Map<String, Object?>.of(
        fixture('ai_direction_fixture-seoul-mapo-b')['trend']
            as Map<String, Object?>,
      )..remove('source');
      final client = fakeBffClient(
        FakeBffAdapter({
          '/districts/$id/direction': (
            status: 200,
            body: envelope({'trend': trend}),
          ),
        }),
      );

      await expectLater(
        RemoteDirectionRepository(client).loadReport(id),
        throwsA(isA<MissingSourceException>()),
      );
    });
  });

  // Provenance holds on the wire as it does in the fixtures.
  test('a live profile without a source is refused', () async {
    final unsourced = fixture('district_fixture-seoul-mapo-b')
      ..remove('source');
    final client = fakeBffClient(
      FakeBffAdapter({
        '/districts/$id/profile': (status: 200, body: envelope(unsourced)),
      }),
    );

    await expectLater(
      RemoteDistrictRepository(client).loadProfile(id),
      throwsA(isA<Exception>()),
    );
  });

  test('a record may come without attendance or votes', () {
    final record = LegislatorRecord.fromJson({
      'bills': {
        'source': {
          'sourceUrl': 'https://open.assembly.go.kr/portal/openapi/main.do',
          'fetchedAt': '2026-09-24T00:00:00Z',
        },
        'items': <Object>[],
      },
    }, field: 'test');

    expect(record, isNotNull);
    expect(record!.attendance, isNull);
    expect(record.votes, isNull);
  });

  group('address search', () {
    test('sends the query and parses suggestions', () async {
      final adapter = FakeBffAdapter({
        '/address/search': (
          status: 200,
          body: envelope(fixture('address_suggestions')),
        ),
      });

      final results = await RemoteAddressSearchRepository(
        fakeBffClient(adapter),
      ).search('  성미산로 ');

      expect(results, isNotEmpty);
      expect(adapter.requests.single.queryParameters, {'q': '성미산로'});
    });

    test('an empty query never reaches the server', () async {
      final adapter = FakeBffAdapter({});

      final results = await RemoteAddressSearchRepository(
        fakeBffClient(adapter),
      ).search('   ');

      expect(results, isEmpty);
      expect(adapter.requests, isEmpty);
    });
  });

  group('location', () {
    FakeBffAdapter resolving() => FakeBffAdapter({
      '/location/district': (
        status: 200,
        body: envelope({
          'district': {'id': id, 'displayName': '서울 마포구 을'},
        }),
      ),
    });

    test('resolves a position to a district', () async {
      final adapter = resolving();

      final result = await RemoteLocationRepository(
        fakeBffClient(adapter),
        positions: _Positions(),
      ).detectDistrict();

      expect(result, isA<LocationResolved>());
      expect((result as LocationResolved).district.id, id);
      // Rounded: a district needs metres, not the device's full precision.
      expect(adapter.requests.single.queryParameters['lat'], '37.55630');
    });

    test('asks once, and a refusal is an outcome, not an error', () async {
      final adapter = resolving();

      final result = await RemoteLocationRepository(
        fakeBffClient(adapter),
        positions: _Positions(
          initial: LocationPermission.denied,
          afterRequest: LocationPermission.denied,
        ),
      ).detectDistrict();

      expect(
        (result as LocationRejected).failure,
        LocationFailure.permissionDenied,
      );
      expect(adapter.requests, isEmpty);
    });

    test('a disabled service says so', () async {
      final result = await RemoteLocationRepository(
        fakeBffClient(resolving()),
        positions: _Positions(enabled: false),
      ).detectDistrict();

      expect(
        (result as LocationRejected).failure,
        LocationFailure.serviceDisabled,
      );
    });

    test('a position outside every district is no match', () async {
      final result = await RemoteLocationRepository(
        fakeBffClient(
          FakeBffAdapter({
            '/location/district': (
              status: 404,
              body: errorEnvelope('no_match'),
            ),
          }),
        ),
        positions: _Positions(),
      ).detectDistrict();

      expect((result as LocationRejected).failure, LocationFailure.noMatch);
    });
  });

  group('live address store', () {
    test('drops a district saved while on fixtures', () async {
      final inner = InMemoryAddressStore(
        const AddressState.readOnly(
          district: DistrictRef(
            id: 'fixture-seoul-mapo-b',
            displayName: '서울 마포구 을',
          ),
        ),
      );

      expect(await LiveAddressStore(inner).read(), isNull);
      expect(await inner.read(), isNull);
    });

    test('keeps a real district', () async {
      const state = AddressState.readOnly(
        district: DistrictRef(id: id, displayName: '서울 마포구 을'),
      );

      final read = await LiveAddressStore(InMemoryAddressStore(state)).read();

      expect(read?.district?.id, id);
    });
  });
}
