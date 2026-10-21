import 'package:democracy/src/core/provenance/source_metadata.dart';

/// The bill a thread was opened from, as the Assembly records it.
class ThreadBill {
  const ThreadBill({
    this.proposer,
    this.committee,
    this.stage,
    this.proposedAt,
  });

  factory ThreadBill.fromJson(Map<Object?, Object?> json) => ThreadBill(
    proposer: _text(json['proposer']),
    committee: _text(json['committee']),
    stage: _text(json['stage']),
    proposedAt: _text(json['proposedAt']),
  );

  /// 「홍길동의원 등 10인」, as the Assembly writes it.
  final String? proposer;
  final String? committee;

  /// 접수, 위원회 심사, 원안가결 and so on. Descriptive only.
  final String? stage;

  /// The proposal date, `YYYY-MM-DD`.
  final String? proposedAt;

  /// `2026. 7. 21.`
  String? get proposedLabel {
    final day = DateTime.tryParse(proposedAt ?? '');
    return day == null ? null : '${day.year}. ${day.month}. ${day.day}.';
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// One thread, opened: what started it and where that is recorded.
class ThreadDetail {
  const ThreadDetail({
    required this.id,
    required this.districtId,
    required this.title,
    required this.origin,
    required this.replies,
    required this.source,
    this.openedAt,
    this.bill,
  });

  factory ThreadDetail.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A thread must be an object.');
    }
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw const FormatException('A thread needs an id and a title.');
    }
    final bill = json['bill'];
    return ThreadDetail(
      id: id,
      districtId: json['districtId'] as String? ?? '',
      title: title,
      origin: json['origin'] as String? ?? '',
      replies: json['replies'] is int ? json['replies']! as int : 0,
      // A thread is a sourced event; without its source it is not shown.
      source: SourceMetadata.fromJson(json['source'], field: 'thread.source'),
      openedAt: json['openedAt'] is String
          ? DateTime.tryParse(json['openedAt']! as String)?.toUtc()
          : null,
      bill: bill is Map ? ThreadBill.fromJson(bill) : null,
    );
  }

  final String id;
  final String districtId;
  final String title;
  final String origin;
  final int replies;
  final SourceMetadata source;
  final DateTime? openedAt;
  final ThreadBill? bill;
}

/// One reply in a thread. Replies are one level deep: nothing answers a
/// reply, and nothing ranks them.
class ThreadReply {
  const ThreadReply({
    required this.id,
    required this.author,
    required this.body,
    required this.verifiedResident,
    this.mine = false,
    this.hidden = false,
    this.authorTag,
    this.createdAt,
  });

  factory ThreadReply.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('A reply must be an object.');
    }
    final id = json['id'];
    final body = json['body'];
    if (id is! String || id.isEmpty || body is! String) {
      throw const FormatException('A reply needs an id and a body.');
    }
    return ThreadReply(
      id: id,
      author: json['author'] as String? ?? '익명 주민',
      body: body,
      verifiedResident: json['verifiedResident'] as bool? ?? false,
      mine: json['mine'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
      authorTag: json['authorTag'] as String?,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt']! as String)?.toUtc()
          : null,
    );
  }

  final String id;
  final String author;
  final String body;
  final bool verifiedResident;
  final bool mine;

  /// Hidden by reports or staff: [body] is the server's placeholder.
  final bool hidden;

  /// Today's opaque tag for the author, on broadcasts only.
  final String? authorTag;
  final DateTime? createdAt;

  ThreadReply asMine() => ThreadReply(
    id: id,
    author: author,
    body: body,
    verifiedResident: verifiedResident,
    mine: true,
    hidden: hidden,
    authorTag: authorTag,
    createdAt: createdAt,
  );

  /// A cursor that starts the next page after this reply. The server's own
  /// cursor carries microseconds; this one may repeat this reply, never skip
  /// one, and a repeat is dropped by id.
  String? get cursor =>
      createdAt == null ? null : '${createdAt!.toIso8601String()}|$id';
}

/// GET /threads/{id}: the thread and one page of its replies, oldest first.
class ThreadPage {
  const ThreadPage({
    required this.thread,
    required this.replies,
    this.nextCursor,
  });

  factory ThreadPage.fromJson(Map<String, Object?> json) {
    final raw = json['replies'];
    final next = json['nextCursor'];
    return ThreadPage(
      thread: ThreadDetail.fromJson(json['thread']),
      replies: List.unmodifiable(
        raw is List ? raw.map(ThreadReply.fromJson) : const <ThreadReply>[],
      ),
      nextCursor: next is String && next.isNotEmpty ? next : null,
    );
  }

  final ThreadDetail thread;
  final List<ThreadReply> replies;

  /// Where the next page starts; null on the last page.
  final String? nextCursor;
}

/// Something that happened in an open thread, from its broadcast topic
/// (`thread:<id>`).
sealed class ThreadEvent {
  const ThreadEvent();

  /// Null for an event this build does not know or a payload it cannot read.
  static ThreadEvent? fromBroadcast(String event, Map<String, Object?> body) {
    try {
      if (event == 'delete' || body['deleted'] == true) {
        final id = body['id'];
        return id is String && id.isNotEmpty ? ReplyDeleted(id) : null;
      }
      if (event == 'reply') {
        return ReplyPosted(ThreadReply.fromJson(body));
      }
      if (event == 'hidden') {
        return ReplyChanged(ThreadReply.fromJson(body));
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

final class ReplyPosted extends ThreadEvent {
  const ReplyPosted(this.reply);

  final ThreadReply reply;
}

/// Hidden by reports or staff, or shown again.
final class ReplyChanged extends ThreadEvent {
  const ReplyChanged(this.reply);

  final ThreadReply reply;
}

final class ReplyDeleted extends ThreadEvent {
  const ReplyDeleted(this.id);

  final String id;
}

/// The topic was joined again after a drop; what was said meanwhile has to
/// be read.
final class ThreadRejoined extends ThreadEvent {
  const ThreadRejoined();
}

/// An open thread as this device knows it.
///
/// [replies] is what the server's pages returned, in its order. Replies that
/// arrive while later pages are still unread -- one's own, or a broadcast --
/// wait in [tail] and are shown after the 「더 보기」, so the pages in between
/// still land in order above them.
class ThreadView {
  const ThreadView({
    required this.thread,
    required this.replies,
    required this.count,
    this.tail = const [],
    this.nextCursor,
    this.loadingMore = false,
  });

  factory ThreadView.first(ThreadPage page) => ThreadView(
    thread: page.thread,
    replies: page.replies,
    count: page.thread.replies,
    nextCursor: page.nextCursor,
  );

  final ThreadDetail thread;
  final List<ThreadReply> replies;
  final List<ThreadReply> tail;

  /// The thread's reply count, moved by what this device saw happen.
  final int count;
  final String? nextCursor;
  final bool loadingMore;

  bool get atEnd => nextCursor == null;

  bool _has(String id) =>
      replies.any((r) => r.id == id) || tail.any((r) => r.id == id);

  ThreadView _copy({
    List<ThreadReply>? replies,
    List<ThreadReply>? tail,
    int? count,
    String? Function()? nextCursor,
    bool? loadingMore,
  }) => ThreadView(
    thread: thread,
    replies: List.unmodifiable(replies ?? this.replies),
    tail: List.unmodifiable(tail ?? this.tail),
    count: count ?? this.count,
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
    loadingMore: loadingMore ?? this.loadingMore,
  );

  ThreadView loading() => _copy(loadingMore: true);

  ThreadView settled() => _copy(loadingMore: false);

  /// More pages wait after what is shown, starting at [cursor].
  ThreadView continuingAt(String? cursor) =>
      cursor == null ? this : _copy(nextCursor: () => cursor);

  /// Appends the next page. Whatever waited in [tail] and is now on a page
  /// leaves the tail; once the last page is in, the tail joins the list.
  ThreadView appendPage(ThreadPage page) {
    final known = {for (final r in replies) r.id};
    final next = [
      ...replies,
      for (final r in page.replies)
        if (!known.contains(r.id)) _keepMine(r),
    ];
    final onPage = {for (final r in next) r.id};
    final waiting = [
      for (final r in tail)
        if (!onPage.contains(r.id)) r,
    ];
    final end = page.nextCursor == null;
    return _copy(
      replies: end ? [...next, ...waiting] : next,
      tail: end ? const [] : waiting,
      nextCursor: () => page.nextCursor,
      loadingMore: false,
    );
  }

  ThreadReply _keepMine(ThreadReply incoming) {
    final mine = tail.any((r) => r.id == incoming.id && r.mine);
    return mine ? incoming.asMine() : incoming;
  }

  /// A reply that is new to this device: one's own, or a broadcast.
  ThreadView add(ThreadReply reply) {
    if (_has(reply.id)) {
      return reply.mine ? _replace(reply) : this;
    }
    return atEnd
        ? _copy(replies: [...replies, reply], count: count + 1)
        : _copy(tail: [...tail, reply], count: count + 1);
  }

  ThreadView apply(ThreadEvent event) => switch (event) {
    ReplyPosted(:final reply) => add(reply),
    ReplyChanged(:final reply) => _replace(reply),
    ReplyDeleted(:final id) => remove(id),
    ThreadRejoined() => this,
  };

  ThreadView remove(String id) {
    if (!_has(id)) {
      return this;
    }
    return _copy(
      replies: [
        for (final r in replies)
          if (r.id != id) r,
      ],
      tail: [
        for (final r in tail)
          if (r.id != id) r,
      ],
      count: count > 0 ? count - 1 : 0,
    );
  }

  ThreadView _replace(ThreadReply reply) {
    ThreadReply swap(ThreadReply r) =>
        r.id != reply.id ? r : (r.mine ? reply.asMine() : reply);
    return _copy(
      replies: replies.map(swap).toList(),
      tail: tail.map(swap).toList(),
    );
  }
}

abstract interface class ThreadRepository {
  /// One page: the first without [after], else the one after that cursor.
  Future<ThreadPage> load(String threadId, {String? after});

  /// Posts a reply and returns it, marked as the reader's own.
  Future<ThreadReply> reply(String threadId, String body);

  Future<void> delete(String replyId);

  /// The thread's broadcasts while listened to; empty without a socket.
  Stream<ThreadEvent> watch(String threadId);
}
