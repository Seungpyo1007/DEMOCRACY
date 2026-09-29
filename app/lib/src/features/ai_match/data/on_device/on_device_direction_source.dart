import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/on_device_ai/on_device_runner.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/data/on_device/issue_run.dart';
import 'package:democracy/src/features/ai_match/data/on_device/stance_run.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/district/domain/district_repository.dart';
import 'package:democracy/src/features/pledges/domain/pledge_repository.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';

/// Blocks 01 and 03 of the direction view, computed by this device's model.
///
/// - 01: each of the sitting member's 22대 pledges placed on the two axes
///   (-1, 0 or +1 each), averaged into one point, with the pledge count.
/// - 03: the member's bills and the district's discussion threads of the last
///   six months, each given one label from a fixed list, counted by month.
///
/// Block 02 (the bill trend) is the server's count and is not touched here.
/// Each block fails on its own: no pledges on record leaves 01 with a note
/// while 03 still runs. The model not being able to run at all is reported
/// once, as [DirectionAiBlocks.unavailable].
class OnDeviceDirectionSource implements DirectionAiSource {
  const OnDeviceDirectionSource({
    required this.runner,
    required this.districts,
    required this.pledges,
    required this.bills,
    required this.community,
  });

  final OnDeviceRunner runner;
  final DistrictRepository districts;
  final PledgeRepository pledges;
  final MemberBillsRepository bills;
  final CommunityRepository community;

  static const _noMember = '현직 의원이 없는 지역구라 분석할 공약·법안이 없습니다.';

  @override
  Future<DirectionAiBlocks> load(String districtId) async {
    final String model;
    try {
      model = await runner.requireModel();
    } on OnDeviceUnavailableException catch (error) {
      return DirectionAiBlocks(unavailable: error.reason);
    }

    final Politician? member;
    try {
      member = (await districts.loadProfile(districtId)).incumbent;
    } on NotAvailableException {
      return const DirectionAiBlocks(
        stancesNote: _noMember,
        issuesNote: _noMember,
      );
    }
    if (member == null) {
      return const DirectionAiBlocks(
        stancesNote: _noMember,
        issuesNote: _noMember,
      );
    }

    try {
      final (stances, stancesNote) = await _block(
        () => _stances(districtId, member!, model),
      );
      final (issues, issuesNote) = await _block(
        () => _issues(districtId, model),
      );
      return DirectionAiBlocks(
        stances: stances,
        stancesNote: stancesNote,
        issues: issues,
        issuesNote: issuesNote,
      );
    } on OnDeviceUnavailableException catch (error) {
      return DirectionAiBlocks(unavailable: error.reason);
    }
  }

  /// A block's value, or null and a note saying why not.
  Future<(T?, String?)> _block<T>(Future<(T?, String?)> Function() run) async {
    try {
      return await run();
    } on OnDeviceModelException catch (error) {
      return (null, error.readerMessage);
    }
  }

  Future<(PolicyStances?, String?)> _stances(
    String districtId,
    Politician member,
    String model,
  ) async {
    final board = await _orNull(() => pledges.loadBoard(districtId));
    if (board == null || board.pledges.isEmpty) {
      return (null, '이 지역구의 공약 목록이 아직 없습니다.');
    }
    final items = pledgeItems(board.pledges);
    final key = onDeviceCacheKey(
      task: OnDeviceTask.stances,
      districtId: districtId,
      input: {
        'member': member.id,
        'pledges': [for (final item in items) item.toFingerprint()],
        'prompt': stancePromptVersion,
      },
      modelVersion: model,
    );

    final cached = await _cached(key, model, (json) {
      return [
        for (final m in (json['marks']! as List).cast<Map<String, Object?>>())
          StanceMark(
            key: m['id']! as String,
            x: m['x']! as int,
            y: m['y']! as int,
          ),
      ];
    });
    final List<StanceMark> marks;
    final OnDeviceRun run;
    if (cached != null) {
      (marks, run) = cached;
    } else {
      marks = [
        for (final batch in _batches(items, stanceBatchSize))
          ...await _batch(
            () async => validateStances(
              decodeModelJson(await runner.generate(stanceRequest(batch))),
              batch,
            ),
          ),
      ];
      if (marks.isEmpty) {
        throw const OnDeviceModelException('output', 'no pledge classified');
      }
      run = OnDeviceRun(generatedAt: runner.now(), model: model);
      await runner.cache.write(key, {
        'marks': [for (final mark in marks) mark.toJson()],
        'generatedAt': run.generatedAt.toIso8601String(),
      });
    }

    return (
      buildStances(
        memberId: member.id,
        memberName: member.name,
        marks: marks,
        source: board.source,
        run: run,
      ),
      null,
    );
  }

  Future<(IssueFlow?, String?)> _issues(String districtId, String model) async {
    final recent = await _orNull(
      () => bills.loadRecent(districtId, months: issueMonths),
    );
    List<DiscussionThread> threads;
    try {
      threads = await community.loadThreads(districtId);
    } on Exception {
      // The threads are extra text; the bills alone still make a flow.
      threads = const [];
    }
    final window = monthWindow(runner.clock.now());
    final items = issueItems(
      bills: recent?.bills ?? const [],
      threads: threads,
      window: window,
    );
    if (recent == null || items.isEmpty) {
      return (null, '최근 ${window.length}개월의 대표발의 법안·토론이 없습니다.');
    }

    final key = onDeviceCacheKey(
      task: OnDeviceTask.issues,
      districtId: districtId,
      input: {
        'items': [for (final item in items) item.toFingerprint()],
        'window': window,
        'prompt': issuePromptVersion,
      },
      modelVersion: model,
    );
    final cached = await _cached(key, model, (json) {
      return [
        for (final m in (json['marks']! as List).cast<Map<String, Object?>>())
          IssueMark(key: m['id']! as String, label: m['label']! as String),
      ];
    });
    final List<IssueMark> marks;
    final OnDeviceRun run;
    if (cached != null) {
      (marks, run) = cached;
    } else {
      marks = [
        for (final batch in _batches(items, issueBatchSize))
          ...await _batch(
            () async => validateIssues(
              decodeModelJson(await runner.generate(issueRequest(batch))),
              batch,
            ),
          ),
      ];
      if (marks.isEmpty) {
        throw const OnDeviceModelException('output', 'no item labelled');
      }
      run = OnDeviceRun(generatedAt: runner.now(), model: model);
      await runner.cache.write(key, {
        'marks': [for (final mark in marks) mark.toJson()],
        'generatedAt': run.generatedAt.toIso8601String(),
      });
    }

    final flow = buildIssueFlow(
      items: items,
      marks: marks,
      window: window,
      source: recent.source,
      run: run,
    );
    return (flow, flow == null ? '분류된 쟁점이 모두 「기타」라 흐름으로 보일 것이 없습니다.' : null);
  }

  /// A batch whose answer did not validate, or that the model declined,
  /// counts nothing -- the count beside the result shows how many were read.
  /// Any other failure (busy, context too long) stops the block.
  Future<List<T>> _batch<T>(Future<List<T>> Function() run) async {
    try {
      return await run();
    } on OnDeviceModelException catch (error) {
      if (error.code == 'output' || error.code == 'guardrail') {
        return const [];
      }
      rethrow;
    }
  }

  Future<(List<T>, OnDeviceRun)?> _cached<T>(
    String key,
    String model,
    List<T> Function(Map<String, Object?> json) read,
  ) async {
    final json = await runner.cache.read(key);
    if (json == null) {
      return null;
    }
    try {
      return (
        read(json),
        OnDeviceRun(
          generatedAt: DateTime.parse(json['generatedAt']! as String).toUtc(),
          model: model,
        ),
      );
    } on Object {
      return null;
    }
  }

  static Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  static Future<T?> _orNull<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on NotAvailableException {
      return null;
    }
  }
}
