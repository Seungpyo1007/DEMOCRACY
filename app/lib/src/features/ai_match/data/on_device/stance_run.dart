import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';

/// The two axes, defined the way this device's model is asked to read them.
///
/// Published with the plot (축 정의 공개), so a reader can check a placement
/// against the rule that produced it.
const onDeviceStanceAxes = StanceAxes(
  xLow: '성장 중심',
  xHigh: '분배 중심',
  yLow: '규제 강화',
  yHigh: '자율 확대',
  xDefinition:
      '공약 한 건마다 경제 성장·투자 확대를 앞세우면 성장(-1), 소득 재분배·복지 확대를 '
      '앞세우면 분배(+1), 어느 쪽도 아니면 0으로 이 기기의 AI가 분류하고, '
      '분류된 공약 전체의 평균을 냈습니다.',
  yDefinition:
      '공약 한 건마다 규제 신설·공공 관리 강화를 제안하면 규제(-1), 규제 완화·민간 자율을 '
      '제안하면 자율(+1), 어느 쪽도 아니면 0으로 이 기기의 AI가 분류하고, '
      '분류된 공약 전체의 평균을 냈습니다.',
);

/// What the section says it was read from.
const onDeviceStanceMethod = '공약 항목별 기기 내 AI 분류(-1·0·+1)의 평균';

const stancePromptVersion = 'stances-v3';

/// The words the model answers with, and the value each stands for.
///
/// Words rather than -1/0/1: asked for numbers, the on-device model put
/// every pledge at 1 on both axes; asked to name the side, it told a
/// special economic zone (성장, 자율) from a child allowance (분배, 중립).
const economyValues = {'성장': -1, '중립': 0, '분배': 1};
const regulationValues = {'규제': -1, '중립': 0, '자율': 1};

/// Pledges per model call. Small: in a batch of 12 the on-device model began
/// giving every pledge the answer it gave the one before.
const stanceBatchSize = 6;

const _stanceInstructions =
    '너는 공약 문구를 정해진 두 축으로 분류하는 도우미다. '
    '문구에 적힌 내용만 보고 판단하며, 좋고 나쁨을 평가하지 않는다. '
    '판단할 근거가 문구에 없으면 중립으로 둔다.';

OnDeviceRequest stanceRequest(List<CitedItem> batch) {
  final buffer = StringBuffer()..writeln('공약:');
  for (final item in batch) {
    buffer.writeln(item.line);
  }
  buffer
    ..writeln()
    ..writeln('모든 공약에 대해 items 항목을 하나씩 만든다. id는 공약 번호 그대로.');
  return OnDeviceRequest(
    task: OnDeviceTask.stances,
    instructions: _stanceInstructions,
    prompt: buffer.toString(),
    format: _stanceFormat,
  );
}

/// The fields, for a model without guided generation (on iOS they are the
/// `@Generable` guides). Kept out of the prompt itself: repeated there, and
/// with a filled-in example, they drew the on-device model to answer 중립
/// for every pledge. The example leaves the values blank for that reason.
///
/// `action` comes first so each pledge is read on its own before its sides
/// are named; without it the model tended to repeat one answer down a
/// batch. The app does not use it.
const _stanceFormat =
    'action: 이 공약이 누구에게 무엇을 하려는지 15자 이내.\n'
    'economy: 성장·투자·산업 육성을 앞세우면 성장, 소득 재분배·복지 지출 확대를 '
    '앞세우면 분배, 어느 쪽도 아니면 중립.\n'
    'regulation: 규제 신설·공공 관리 강화를 제안하면 규제, 규제 완화·민간 자율을 '
    '제안하면 자율, 어느 쪽도 아니면 중립.\n'
    '형식(JSON만): {"items":[{"id":"...","action":"...","economy":"...",'
    '"regulation":"..."}]}';

/// One pledge's placement.
class StanceMark {
  const StanceMark({required this.key, required this.x, required this.y});

  final String key;

  /// -1, 0 or 1.
  final int x;
  final int y;

  Map<String, Object?> toJson() => {'id': key, 'x': x, 'y': y};
}

/// Checks one batch's answer.
///
/// An item must name a pledge in this batch, once, with both sides named by
/// exactly one of the listed words ([economyValues], [regulationValues]).
/// Anything else -- a number, another word, a pledge from another batch or
/// none at all -- is dropped: the pledge simply is not counted, which the
/// count beside the plot then shows.
List<StanceMark> validateStances(
  Map<String, Object?> json,
  List<CitedItem> batch,
) {
  final raw = json['items'];
  if (raw is! List) {
    throw const OnDeviceModelException('output', 'no items');
  }
  final keys = {for (final item in batch) item.key};
  final seen = <String>{};
  final marks = <StanceMark>[];
  for (final entry in raw.whereType<Map<Object?, Object?>>()) {
    final key = normaliseKey(entry['id']);
    final x = economyValues[_word(entry['economy'])];
    final y = regulationValues[_word(entry['regulation'])];
    if (key == null ||
        !keys.contains(key) ||
        seen.contains(key) ||
        x == null ||
        y == null) {
      continue;
    }
    seen.add(key);
    marks.add(StanceMark(key: key, x: x, y: y));
  }
  return marks;
}

String? _word(Object? value) => value is String ? value.trim() : null;

/// The member's one point: the mean of every classified pledge.
///
/// Null when no pledge was classified -- no point is better than a point at
/// the centre that nothing put there.
PolicyStances? buildStances({
  required String memberId,
  required String memberName,
  required List<StanceMark> marks,
  required SourceMetadata source,
  required OnDeviceRun run,
}) {
  if (marks.isEmpty) {
    return null;
  }
  double mean(int Function(StanceMark mark) axis) =>
      marks.fold<int>(0, (sum, mark) => sum + axis(mark)) / marks.length;
  return PolicyStances(
    axes: onDeviceStanceAxes,
    subject: MatchSubject.incumbent,
    onDevice: run,
    source: source,
    candidates: [
      CandidateStance(
        candidateId: memberId,
        name: memberName,
        x: mean((mark) => mark.x),
        y: mean((mark) => mark.y),
        pledgeCount: marks.length,
      ),
    ],
  );
}
