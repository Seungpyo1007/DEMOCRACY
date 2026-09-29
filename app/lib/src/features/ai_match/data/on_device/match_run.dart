import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/domain/candidate_match.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';

/// Everything one on-device match reads.
///
/// Between elections there are no candidates, so the run compares the
/// reader's interests with the sitting member's 22대 pledges (from the
/// 선거공보) and the bills they led in the last few months.
class MatchInput {
  MatchInput({
    required this.memberId,
    required this.memberName,
    required this.party,
    required this.interests,
    required this.context,
    required this.pledges,
    required this.bills,
    required this.billMonths,
  }) : items = byKey([...pledges, ...bills]);

  final String memberId;
  final String memberName;
  final PartyRef party;
  final List<String> interests;
  final List<String> context;
  final List<CitedItem> pledges;
  final List<CitedItem> bills;
  final int billMonths;

  /// Every key the model may cite.
  final Map<String, CitedItem> items;

  /// What the cache key hashes.
  Map<String, Object?> toFingerprint() => {
    'member': memberId,
    'interests': interests,
    'context': context,
    'pledges': [for (final p in pledges) p.toFingerprint()],
    'bills': [for (final b in bills) b.toFingerprint()],
    'prompt': matchPromptVersion,
  };
}

/// Bumped whenever the instructions change, so cached answers to the old
/// wording are not served as answers to the new one.
const matchPromptVersion = 'match-v1';

/// The most pledges and bills one run reads. A small on-device context has
/// room for about this much Korean alongside the instructions and the answer.
const matchMaxPledges = 30;
const matchMaxBills = 25;

/// At most this many reasons per interest are kept.
const matchReasonsPerAxis = 2;

/// Longest reason kept; a model that writes a paragraph was not answering
/// the question asked.
const matchReasonMaxLength = 160;

const _matchInstructions =
    '너는 국회의원의 공약과 대표발의 법안 제목을 읽고, 독자가 고른 관심 분야와 '
    '얼마나 직접 관련되는지를 판단하는 분류 도우미다. '
    '추천, 지지, 평가, 칭찬, 비판을 하지 않는다. '
    '입력에 적힌 항목만 근거로 쓰고, 근거마다 그 항목의 번호(P1, B2 같은)를 그대로 적는다. '
    '입력에 없는 사실, 수치, 약속을 만들지 않는다.';

OnDeviceRequest matchRequest(MatchInput input) {
  final buffer = StringBuffer()
    ..writeln('관심 분야: ${input.interests.join(', ')}');
  if (input.context.isNotEmpty) {
    buffer.writeln('독자 상황(참고만): ${input.context.join(', ')}');
  }
  buffer
    ..writeln()
    ..writeln('${input.memberName} 의원의 22대 총선 공약:');
  if (input.pledges.isEmpty) {
    buffer.writeln('(없음)');
  }
  for (final item in input.pledges) {
    buffer.writeln(item.line);
  }
  buffer
    ..writeln()
    ..writeln('최근 ${input.billMonths}개월 대표발의 법안:');
  if (input.bills.isEmpty) {
    buffer.writeln('(없음)');
  }
  for (final item in input.bills) {
    buffer.writeln(item.line);
  }
  buffer
    ..writeln()
    ..writeln('관심 분야마다 axes 항목을 하나씩 만든다.')
    ..writeln('label: 관심 분야 이름을 그대로 쓴다.')
    ..writeln(
      'score: 0~100 정수. 그 분야를 직접 다루는 공약·법안이 많고 구체적일수록 높다. '
      '관련 항목이 없으면 0.',
    )
    ..writeln(
      'reasons: 최대 $matchReasonsPerAxis개. id는 위 번호 하나, '
      'text는 그 항목이 이 분야와 어떻게 관련되는지 60자 이내 한 문장(사실만).',
    )
    ..writeln(
      '형식(JSON만): {"axes":[{"label":"...","score":0,'
      '"reasons":[{"id":"P1","text":"..."}]}]}',
    );

  return OnDeviceRequest(
    task: OnDeviceTask.match,
    instructions: _matchInstructions,
    prompt: buffer.toString(),
  );
}

/// One reason that survived validation.
class VerifiedReason {
  const VerifiedReason({required this.key, required this.text});

  final String key;
  final String text;

  Map<String, Object?> toJson() => {'id': key, 'text': text};
}

/// One interest's score, and the reasons behind it that checked out.
class VerifiedAxis {
  const VerifiedAxis({
    required this.label,
    required this.score,
    required this.reasons,
    required this.modelScore,
  });

  final String label;

  /// 0..100. Zero when no cited reason checked out -- see [validateMatch].
  final int score;

  /// What the model said before the no-evidence rule, for the audit page.
  final int modelScore;
  final List<VerifiedReason> reasons;

  Map<String, Object?> toJson() => {
    'label': label,
    'score': score,
    'modelScore': modelScore,
    'reasons': [for (final r in reasons) r.toJson()],
  };
}

/// The model's answer, after the app has checked it.
class VerifiedMatch {
  const VerifiedMatch({
    required this.axes,
    required this.droppedReasons,
    required this.rejectedAxes,
  });

  /// Reads a cached answer back. It was validated before it was stored.
  factory VerifiedMatch.fromCache(Map<String, Object?> json) {
    final raw = json['axes'];
    return VerifiedMatch(
      axes: [
        if (raw is List)
          for (final axis in raw.whereType<Map<String, Object?>>())
            VerifiedAxis(
              label: axis['label']! as String,
              score: axis['score']! as int,
              modelScore: axis['modelScore']! as int,
              reasons: [
                for (final r
                    in (axis['reasons']! as List)
                        .whereType<Map<String, Object?>>())
                  VerifiedReason(
                    key: r['id']! as String,
                    text: r['text']! as String,
                  ),
              ],
            ),
      ],
      droppedReasons: json['droppedReasons'] is int
          ? json['droppedReasons']! as int
          : 0,
      rejectedAxes: json['rejectedAxes'] is int
          ? json['rejectedAxes']! as int
          : 0,
    );
  }

  final List<VerifiedAxis> axes;

  /// Reasons thrown out: an id not in the input, an empty or overlong text,
  /// a repeat.
  final int droppedReasons;

  /// Axes thrown out: an interest the reader did not pick, a repeat, or a
  /// score that is not a number from 0 to 100.
  final int rejectedAxes;

  Map<String, Object?> toJson() => {
    'axes': [for (final a in axes) a.toJson()],
    'droppedReasons': droppedReasons,
    'rejectedAxes': rejectedAxes,
  };
}

/// Checks the model's answer against its input, keeping only what holds.
///
/// - An axis must name one of the reader's interests, once, with a score that
///   is a number from 0 to 100. A score outside the scale is rejected rather
///   than clamped: a model that answered 140 did not use the scale it was
///   given, and pulling the number back to 100 would hide that.
/// - A reason must cite a key that is in the input and say something. Any
///   other citation is a source the reader was never shown and is dropped.
/// - An axis left with no verified reason scores 0. A relevance claim with
///   nothing behind it that the reader can open is not shown as one.
///
/// Throws [OnDeviceModelException] (`output`) when nothing usable is left.
VerifiedMatch validateMatch(Map<String, Object?> json, MatchInput input) {
  final raw = json['axes'];
  if (raw is! List) {
    throw const OnDeviceModelException('output', 'no axes');
  }

  final seen = <String>{};
  final axes = <VerifiedAxis>[];
  var dropped = 0;
  var rejected = 0;

  for (final entry in raw) {
    if (entry is! Map) {
      rejected++;
      continue;
    }
    final label = entry['label'] is String
        ? (entry['label']! as String).trim()
        : '';
    final score = entry['score'];
    if (!input.interests.contains(label) ||
        seen.contains(label) ||
        score is! num ||
        !score.isFinite ||
        score < 0 ||
        score > 100) {
      rejected++;
      final reasons = entry['reasons'];
      if (reasons is List) {
        dropped += reasons.length;
      }
      continue;
    }
    seen.add(label);

    final reasons = <VerifiedReason>[];
    final cited = <String>{};
    final rawReasons = entry['reasons'];
    for (final reason in rawReasons is List ? rawReasons : const []) {
      final verified = reason is Map ? _verifyReason(reason, input) : null;
      if (verified == null ||
          cited.contains(verified.key) ||
          reasons.length >= matchReasonsPerAxis) {
        dropped++;
        continue;
      }
      cited.add(verified.key);
      reasons.add(verified);
    }

    final modelScore = score.round();
    axes.add(
      VerifiedAxis(
        label: label,
        modelScore: modelScore,
        score: reasons.isEmpty ? 0 : modelScore,
        reasons: List.unmodifiable(reasons),
      ),
    );
  }

  if (axes.isEmpty) {
    throw const OnDeviceModelException('output', 'no valid axis');
  }

  // The reader's order, whatever order the model answered in.
  axes.sort(
    (a, b) =>
        input.interests.indexOf(a.label) - input.interests.indexOf(b.label),
  );

  return VerifiedMatch(
    axes: List.unmodifiable(axes),
    droppedReasons: dropped,
    rejectedAxes: rejected,
  );
}

VerifiedReason? _verifyReason(Map<Object?, Object?> raw, MatchInput input) {
  final key = normaliseKey(raw['id']);
  final text = raw['text'] is String ? (raw['text']! as String).trim() : '';
  if (key == null ||
      !input.items.containsKey(key) ||
      text.isEmpty ||
      text.length > matchReasonMaxLength) {
    return null;
  }
  return VerifiedReason(key: key, text: text);
}

/// Reasons that have checked out in a snapshot of a run still going.
///
/// The last reason in the snapshot may still be mid-sentence, so it is held
/// back unless [complete]. The same checks as [validateMatch] apply.
List<VerifiedReason> verifiedSoFar(
  Map<String, Object?> snapshot,
  MatchInput input, {
  bool complete = false,
}) {
  final raw = snapshot['axes'];
  if (raw is! List) {
    return const [];
  }
  final all = <(String, Map<Object?, Object?>)>[];
  for (final axis in raw.whereType<Map<Object?, Object?>>()) {
    final label = axis['label'];
    final reasons = axis['reasons'];
    if (label is! String || !input.interests.contains(label.trim())) {
      continue;
    }
    if (reasons is List) {
      for (final reason in reasons.whereType<Map<Object?, Object?>>()) {
        all.add((label.trim(), reason));
      }
    }
  }
  final settled = complete || all.isEmpty
      ? all
      : all.sublist(0, all.length - 1);
  return [for (final (_, reason) in settled) ?_verifyReason(reason, input)];
}

/// Turns a verified answer into the report the screen draws.
///
/// The overall score is the plain mean of the axis scores -- every interest
/// counts the same, and the audit page says so.
MatchReport buildMatchReport({
  required MatchInput input,
  required VerifiedMatch verified,
  required OnDeviceRun run,
}) {
  final axes = verified.axes;
  final mean = axes.fold<int>(0, (sum, axis) => sum + axis.score) / axes.length;
  final reasons = [
    for (final axis in axes)
      for (final reason in axis.reasons)
        reasonFor(reason, input, axis: axis.label),
  ];

  final parts = [
    '22대 공약 ${input.pledges.length}건',
    '최근 ${input.billMonths}개월 대표발의 ${input.bills.length}건',
  ];

  return MatchReport(
    subject: MatchSubject.incumbent,
    comparedPledges: input.pledges.length,
    comparedBills: input.bills.length,
    generatedAt: run.generatedAt,
    onDevice: run,
    weights: {
      'model': run.model,
      'generatedOn': '이 기기 (서버로 보내지 않음)',
      'prompt': matchPromptVersion,
      'sampling': 'greedy (같은 입력이면 같은 결과)',
      'inputs': {
        'interests': input.interests,
        'context': input.context,
        'pledges': input.pledges.length,
        'bills': input.bills.length,
        'billMonths': input.billMonths,
      },
      'axisWeights': {for (final axis in axes) axis.label: 1 / axes.length},
      'score': '관심 분야별 관련도(0~100)의 단순 평균',
      'verification':
          '근거마다 인용한 공약·법안 번호가 입력에 있는지 확인하고 없으면 버림. '
          '확인된 근거가 없는 분야는 0점. 0~100을 벗어난 점수는 버림.',
      'modelScores': {for (final axis in axes) axis.label: axis.modelScore},
      'droppedReasons': verified.droppedReasons,
      'rejectedAxes': verified.rejectedAxes,
      'disclaimer': '공약 원문 기반 참고 자료이며 공인 평가가 아닙니다.',
    },
    matches: [
      CandidateMatch(
        candidateId: input.memberId,
        name: input.memberName,
        party: input.party,
        score: mean,
        headline: '${parts.join(' · ')}와 대조',
        axes: [
          for (final axis in axes)
            MatchAxis(label: axis.label, score: axis.score.toDouble()),
        ],
        reasons: List.unmodifiable(reasons),
      ),
    ],
  );
}

MatchReason reasonFor(VerifiedReason reason, MatchInput input, {String? axis}) {
  final item = input.items[reason.key]!;
  return MatchReason(
    text: reason.text,
    source: item.source,
    axis: axis,
    cites: switch (item.kind) {
      CitedKind.pledge => '공약 「${item.title}」',
      CitedKind.bill => '법안 「${item.title}」',
      CitedKind.thread => '토론 「${item.title}」',
    },
  );
}
