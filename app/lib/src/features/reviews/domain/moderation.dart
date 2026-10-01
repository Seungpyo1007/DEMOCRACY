/// Reports (신고) and blocks (차단), as the app sees them.
///
/// A report names a post and a reason; the server decides whether the post
/// is hidden at once (personal information, or three readers) and staff
/// decide the rest. A block names a post, never a person: the server finds
/// the author, and the reader only ever learns how that author showed and a
/// tag that changes every day.
library;

enum PostKind {
  review('review'),
  message('message');

  const PostKind(this.wire);

  final String wire;
}

enum ReportReason {
  hate('hate', '혐오·욕설'),
  privacy('privacy', '개인정보 노출', '이름과 연락처, 주소 같은 정보'),
  falseClaim('false', '허위사실', '사실이 아닌 내용. 운영자가 확인한 뒤에만 가립니다'),
  spam('spam', '도배·광고'),
  other('other', '기타');

  const ReportReason(this.wire, this.label, [this.detail]);

  final String wire;
  final String label;
  final String? detail;
}

class BlockedAuthor {
  const BlockedAuthor({
    required this.id,
    required this.label,
    required this.createdAt,
    this.authorTag,
  });

  factory BlockedAuthor.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A block must be an object.');
    }
    final id = json['id'];
    final label = json['label'];
    final at = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id is! String || label is! String || at == null) {
      throw const FormatException('A block needs an id, a label and a date.');
    }
    return BlockedAuthor(
      id: id,
      label: label,
      createdAt: at,
      authorTag: json['authorTag'] as String?,
    );
  }

  final String id;

  /// How the author showed when blocked: a 활동명, or 익명 주민.
  final String label;
  final DateTime createdAt;

  /// Today's tag of the author, for leaving their live messages out.
  final String? authorTag;
}

/// What came of a report.
enum ReportOutcome {
  /// Filed; staff will look at it.
  filed,

  /// Filed, and the post is hidden for everyone from now.
  hidden,
}

/// A report or block the server refused, with what to tell the reader.
class ModerationException implements Exception {
  const ModerationException(this.message);

  factory ModerationException.fromCode(String code) => switch (code) {
    'conflict' => const ModerationException('이미 신고한 글입니다.'),
    'rate_limited' => const ModerationException(
      '오늘은 더 신고할 수 없습니다. 내일 다시 시도하세요.',
    ),
    'not_found' => const ModerationException('이미 지워진 글입니다.'),
    'bad_request' => const ModerationException('이 글은 신고하거나 숨길 수 없습니다.'),
    _ => generic,
  };

  static const generic = ModerationException('처리하지 못했습니다. 잠시 뒤 다시 시도하세요.');

  final String message;

  @override
  String toString() => 'ModerationException: $message';
}

abstract interface class ModerationRepository {
  Future<ReportOutcome> report(
    PostKind kind,
    String id,
    ReportReason reason, {
    String? note,
  });

  Future<BlockedAuthor> block(PostKind kind, String id);

  Future<void> unblock(String blockId);

  Future<List<BlockedAuthor>> loadBlocks();
}
