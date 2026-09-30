import 'dart:async';

import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/on_device_ai/on_device_runner.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/data/on_device/match_run.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';

/// The match, computed by the model on this device.
///
/// There is no election on, so there are no candidates: the run reads the
/// sitting member's 22대 pledges and their bills of the last six months
/// against the interests the reader picked, and returns one entry -- the
/// member -- with a relevance score per interest and reasons that each cite
/// a pledge or bill by its own link. Every citation is checked against the
/// input before anything is shown ([validateMatch]).
///
/// Nothing here talks to a model server. The input is public record fetched
/// from the BFF; the output stays on the device, cached per district, input
/// and model version.
class OnDeviceMatchRepository implements MatchRepository, MatchProgressSource {
  OnDeviceMatchRepository({
    required this.runner,
    required this.districts,
    required this.pledges,
    required this.bills,
    this.billMonths = 6,
  });

  final OnDeviceRunner runner;
  final DistrictRepository districts;
  final PledgeRepository pledges;
  final MemberBillsRepository bills;
  final int billMonths;

  final _progress = StreamController<MatchProgress>.broadcast();

  /// The last report per district, for [streamReasoning].
  final _reports = <String, MatchReport>{};

  @override
  Stream<MatchProgress> get progress => _progress.stream;

  @override
  Future<MatchReport> loadReport(
    String districtId, {
    MatchQuery query = const MatchQuery(),
  }) async {
    final model = await runner.requireModel();
    if (query.interests.isEmpty) {
      throw const MatchNeedsInterestsException();
    }

    final input = await _input(districtId, query);
    final key = onDeviceCacheKey(
      task: OnDeviceTask.match,
      districtId: districtId,
      input: input.toFingerprint(),
      modelVersion: model,
    );

    final cached = await _fromCache(key, model);
    final (verified, run) = cached ?? await _run(input, model);
    if (cached == null) {
      await runner.cache.write(key, {
        'output': verified.toJson(),
        'generatedAt': run.generatedAt.toIso8601String(),
      });
    }

    final report = buildMatchReport(input: input, verified: verified, run: run);
    _reports[districtId] = report;
    return report;
  }

  Future<MatchInput> _input(String districtId, MatchQuery query) async {
    final profile = await districts.loadProfile(districtId);
    final member = profile.incumbent;
    if (member == null) {
      throw const NotAvailableException('no sitting member');
    }

    List<Pledge> pledgeList;
    try {
      pledgeList = (await pledges.loadBoard(districtId)).pledges;
    } on NotAvailableException {
      pledgeList = const [];
    }
    List<BillDigest> billList;
    try {
      billList = (await bills.loadRecent(districtId, months: billMonths)).bills;
    } on NotAvailableException {
      billList = const [];
    }
    if (pledgeList.isEmpty && billList.isEmpty) {
      throw const NotAvailableException('nothing to compare');
    }

    return MatchInput(
      memberId: member.id,
      memberName: member.name,
      party: member.party,
      interests: query.interests,
      context: query.context,
      pledges: pledgeItems(pledgeList.take(matchMaxPledges)),
      bills: billItems(billList.take(matchMaxBills)),
      billMonths: billMonths,
    );
  }

  Future<(VerifiedMatch, OnDeviceRun)?> _fromCache(
    String key,
    String model,
  ) async {
    final cached = await runner.cache.read(key);
    if (cached == null) {
      return null;
    }
    try {
      final output = cached['output']! as Map<String, Object?>;
      final at = DateTime.parse(cached['generatedAt']! as String).toUtc();
      return (
        VerifiedMatch.fromCache(output),
        OnDeviceRun(generatedAt: at, model: model),
      );
    } on Object {
      // An entry this build cannot read is a miss, not a failure.
      return null;
    }
  }

  Future<(VerifiedMatch, OnDeviceRun)> _run(
    MatchInput input,
    String model,
  ) async {
    _progress.add(const MatchProgress(verified: [], characters: 0));
    final text = await runner.generateStreaming(matchRequest(input), (
      snapshot,
    ) {
      final partial = tryDecodeModelJson(snapshot);
      _progress.add(
        MatchProgress(
          characters: snapshot.length,
          verified: [
            if (partial != null)
              for (final reason in verifiedSoFar(partial, input))
                reasonFor(reason, input),
          ],
        ),
      );
    });
    final verified = validateMatch(decodeModelJson(text), input);
    return (verified, OnDeviceRun(generatedAt: runner.now(), model: model));
  }

  /// The verified reasons, once. They are only shown after every citation
  /// has been checked, so there is nothing to stream token by token here;
  /// the run itself streams while it is going (see [progress]).
  @override
  Stream<String> streamReasoning(String districtId, String candidateId) async* {
    final report = _reports[districtId];
    final match = report?.matches
        .where((candidate) => candidate.candidateId == candidateId)
        .firstOrNull;
    if (match == null || match.reasons.isEmpty) {
      return;
    }
    yield match.reasons.map((reason) => reason.text).join(' ');
  }
}
