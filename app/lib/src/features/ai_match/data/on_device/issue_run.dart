import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/on_device_run.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/core/time/kst.dart';
import 'package:democracy/src/features/ai_match/data/on_device/cited_items.dart';
import 'package:democracy/src/features/ai_match/domain/direction_report.dart';
import 'package:democracy/src/features/ai_match/domain/member_bills.dart';
import 'package:democracy/src/features/reviews/domain/review_draft.dart';

/// The labels an item may be given. Fixed, so a count of 교통 this month
/// means the same thing as a count of 교통 last month, and a label the model
/// invents is simply not one of them.
const issueLabels = [
  '주거·부동산',
  '교통',
  '교육·보육',
  '복지·돌봄',
  '보건·의료',
  '일자리·경제',
  '안전·재난',
  '환경·에너지',
  '문화·체육',
  '행정·제도',
  '기타',
];

/// The catch-all, counted but never shown as an issue.
const issueOther = '기타';

/// What the flow says it was counted from. No 민원, no 보도: the app has
/// neither, and a basis line that named them would be claiming a reading
/// nobody did.
const onDeviceIssueBasis = '대표발의 법안·토론 제목 기준 · 기기 내 AI 분류';

const issuePromptVersion = 'issues-v1';
const issueBatchSize = 15;
const issueMonths = 6;

/// How many issues the section lists at most.
const issueShown = 5;

const _issueInstructions =
    '너는 법안과 토론 제목을 정해진 쟁점 목록 중 하나로 분류하는 도우미다. '
    '제목에 적힌 내용만 보고 판단하며, 좋고 나쁨을 평가하지 않는다. '
    '목록에 없는 쟁점 이름을 만들지 않는다.';

/// The last [months] KST months, oldest first, as `YYYY-MM`.
List<String> monthWindow(KstInstant now, {int months = issueMonths}) {
  final wall = now.wallClock;
  return [
    for (var back = months - 1; back >= 0; back--)
      _yearMonth(DateTime.utc(wall.year, wall.month - back)),
  ];
}

String _yearMonth(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// The text the flow counts: the member's bills, and discussion threads that
/// are not one of those bills, inside [window].
///
/// Today every thread is opened from one of the member's bills, so most
/// threads are the same text as a bill and are counted once, as the bill.
List<CitedItem> issueItems({
  required List<BillDigest> bills,
  required List<DiscussionThread> threads,
  required List<String> window,
}) {
  final months = window.toSet();
  final billIds = {for (final bill in bills) bill.id};
  final items = <CitedItem>[];
  for (final bill in bills) {
    if (months.contains(bill.month)) {
      items.add(
        CitedItem(
          key: 'I${items.length + 1}',
          id: bill.id,
          title: bill.title,
          kind: CitedKind.bill,
          source: bill.source,
          month: bill.month,
        ),
      );
    }
  }
  for (final thread in threads) {
    final opened = thread.openedAt;
    final url = thread.sourceUrl;
    if (opened == null || url == null) {
      continue;
    }
    final isBill =
        thread.origin == 'bill' &&
        (billIds.contains(thread.id.replaceFirst('bill-', '')) ||
            bills.any((bill) => bill.source.sourceUrl == url));
    final month = _yearMonth(KstInstant.fromDateTime(opened).wallClock);
    if (isBill || !months.contains(month)) {
      continue;
    }
    final SourceMetadata source;
    try {
      source = SourceMetadata(sourceUrl: url, fetchedAt: opened);
    } on ArgumentError {
      continue;
    }
    items.add(
      CitedItem(
        key: 'I${items.length + 1}',
        id: thread.id,
        title: thread.title,
        kind: CitedKind.thread,
        source: source,
        month: month,
      ),
    );
  }
  return items;
}

OnDeviceRequest issueRequest(List<CitedItem> batch) {
  final buffer = StringBuffer()
    ..writeln('쟁점 목록: ${issueLabels.join(', ')}')
    ..writeln()
    ..writeln('제목:');
  for (final item in batch) {
    buffer.writeln('${item.key} ${item.title}');
  }
  buffer
    ..writeln()
    ..writeln('모든 제목에 대해 items 항목을 하나씩 만든다. id는 번호 그대로.')
    ..writeln('label: 제목이 주로 다루는 쟁점을 목록에서 하나만 골라 그대로 쓴다.')
    ..writeln('형식(JSON만): {"items":[{"id":"I1","label":"교통"}]}');
  return OnDeviceRequest(
    task: OnDeviceTask.issues,
    instructions: _issueInstructions,
    prompt: buffer.toString(),
  );
}

/// One item's label.
class IssueMark {
  const IssueMark({required this.key, required this.label});

  final String key;
  final String label;

  Map<String, Object?> toJson() => {'id': key, 'label': label};
}

/// Checks one batch's answer: a known key from this batch, once, with a label
/// from [issueLabels] exactly. Anything else is not counted.
List<IssueMark> validateIssues(
  Map<String, Object?> json,
  List<CitedItem> batch,
) {
  final raw = json['items'];
  if (raw is! List) {
    throw const OnDeviceModelException('output', 'no items');
  }
  final keys = {for (final item in batch) item.key};
  final seen = <String>{};
  final marks = <IssueMark>[];
  for (final entry in raw.whereType<Map<Object?, Object?>>()) {
    final key = normaliseKey(entry['id']);
    final label = entry['label'] is String
        ? (entry['label']! as String).trim()
        : '';
    if (key == null ||
        !keys.contains(key) ||
        seen.contains(key) ||
        !issueLabels.contains(label)) {
      continue;
    }
    seen.add(key);
    marks.add(IssueMark(key: key, label: label));
  }
  return marks;
}

/// Monthly counts per label, most-mentioned first, 기타 left out.
///
/// Null when nothing but 기타 (or nothing at all) was counted.
IssueFlow? buildIssueFlow({
  required List<CitedItem> items,
  required List<IssueMark> marks,
  required List<String> window,
  required SourceMetadata source,
  required OnDeviceRun run,
}) {
  final monthOf = {for (final item in items) item.key: item.month};
  final counts = <String, List<int>>{};
  for (final mark in marks) {
    if (mark.label == issueOther) {
      continue;
    }
    final index = window.indexOf(monthOf[mark.key] ?? '');
    if (index < 0) {
      continue;
    }
    (counts[mark.label] ??= List.filled(window.length, 0))[index]++;
  }
  if (counts.isEmpty) {
    return null;
  }
  int total(List<int> monthly) => monthly.fold(0, (sum, n) => sum + n);
  final ordered = counts.entries.toList()
    ..sort((a, b) {
      final byCount = total(b.value).compareTo(total(a.value));
      return byCount != 0
          ? byCount
          : issueLabels.indexOf(a.key) - issueLabels.indexOf(b.key);
    });
  return IssueFlow(
    period: '최근 ${window.length}개월',
    basis: onDeviceIssueBasis,
    source: source,
    onDevice: run,
    issues: [
      for (final entry in ordered.take(issueShown))
        LocalIssue(label: entry.key, monthly: List.unmodifiable(entry.value)),
    ],
  );
}
