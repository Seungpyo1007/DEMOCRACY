import 'dart:convert';

import 'package:democracy/src/core/fixtures/fixture_loader.dart';
import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';

/// A model that answers from a script, so validation and caching can be
/// tested without a device.
///
/// [answer] maps each request to the JSON the model "wrote". [stream] sends
/// the answer in growing halves, the way iOS sends partial snapshots.
class ScriptedOnDeviceModel implements OnDeviceModel {
  ScriptedOnDeviceModel({
    required this.answer,
    this.status = const ModelAvailable('test-model-1'),
  });

  Object? Function(OnDeviceRequest request) answer;
  ModelAvailability status;

  final requests = <OnDeviceRequest>[];
  var prepared = 0;

  @override
  Future<ModelAvailability> availability() async => status;

  @override
  Future<void> prepare() async => prepared++;

  String _text(OnDeviceRequest request) {
    requests.add(request);
    final value = answer(request);
    if (value is Exception) {
      throw value;
    }
    return value is String ? value : jsonEncode(value);
  }

  @override
  Future<String> generate(OnDeviceRequest request) async => _text(request);

  @override
  Stream<String> stream(OnDeviceRequest request) async* {
    final text = _text(request);
    yield text.substring(0, text.length ~/ 2);
    yield text;
  }
}

/// The member's bills from the sample fixture.
class FixtureMemberBillsRepository implements MemberBillsRepository {
  const FixtureMemberBillsRepository(this.loader);

  final FixtureLoader loader;

  @override
  Future<MemberBills> loadRecent(String districtId, {int months = 6}) async {
    final payload = await loader.load('member_bills_$districtId');
    return MemberBills.fromJson(payload);
  }
}

/// A district with no bills on record.
class NoMemberBillsRepository implements MemberBillsRepository {
  const NoMemberBillsRepository();

  @override
  Future<MemberBills> loadRecent(String districtId, {int months = 6}) =>
      Future.error(const NotAvailableException('bills'));
}
