import 'package:democracy/src/features/reviews/domain/review_draft.dart';

/// Something that happened in a district channel after it was read.
///
/// The server broadcasts these (topic `district-chat:<district id>`); this
/// device also produces one for each message it sends, from the POST answer.
/// Both are folded into the list the screen shows by [ChannelLog.apply].
sealed class ChannelEvent {
  const ChannelEvent();

  /// Reads one broadcast. Null for an event this build does not know, or a
  /// payload that is not a message: an unknown event is skipped rather than
  /// dropping the connection, so the server can add one without breaking
  /// older apps.
  static ChannelEvent? fromBroadcast(String event, Map<String, Object?> body) {
    try {
      if (event == 'delete' || body['deleted'] == true) {
        final id = body['id'];
        return id is String && id.isNotEmpty ? MessageDeleted(id) : null;
      }
      if (event == 'message') {
        return MessagePosted(ChatMessage.fromJson(body));
      }
      if (event == 'hidden') {
        return MessageChanged(ChatMessage.fromJson(body));
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// A message was posted, by anyone.
final class MessagePosted extends ChannelEvent {
  const MessagePosted(this.message);

  final ChatMessage message;
}

/// A message was hidden by reports or staff, or shown again.
final class MessageChanged extends ChannelEvent {
  const MessageChanged(this.message);

  final ChatMessage message;
}

/// A message was deleted by its author.
final class MessageDeleted extends ChannelEvent {
  const MessageDeleted(this.id);

  final String id;
}

/// The channel as this device knows it: the last read, plus what arrived
/// since. Immutable; every change returns a new log.
///
/// A message can reach the device twice -- the sender gets it back from the
/// POST and again from the broadcast, and a re-read after a reconnect repeats
/// what the socket already delivered -- so messages are kept by id and a
/// second copy is dropped. The one exception is `mine`: the broadcast cannot
/// know who is reading, so a copy that says the message is the reader's own
/// wins over one that does not, whichever came first.
class ChannelLog {
  const ChannelLog._(this.messages);

  /// The channel as last read, oldest first.
  factory ChannelLog.read(List<ChatMessage> messages) =>
      const ChannelLog._([]).merge(messages);

  static const empty = ChannelLog._([]);

  /// How many messages are kept. The server sends the newest 50 on a read;
  /// a screen left open keeps a few hundred rather than growing without end.
  static const capacity = 200;

  final List<ChatMessage> messages;

  ChannelLog apply(ChannelEvent event) => switch (event) {
    MessagePosted(:final message) => merge([message]),
    MessageChanged(:final message) => replace(message),
    MessageDeleted(:final id) =>
      messages.any((m) => m.id == id)
          ? ChannelLog._(List.unmodifiable(messages.where((m) => m.id != id)))
          : this,
  };

  /// Puts [message] in place of the one with its id, keeping whether it is
  /// the reader's own; a message this device never had is left out.
  ChannelLog replace(ChatMessage message) {
    final i = messages.indexWhere((m) => m.id == message.id);
    if (i < 0) {
      return this;
    }
    final next = [...messages];
    next[i] = next[i].mine ? message.asMine() : message;
    return ChannelLog._(List.unmodifiable(next));
  }

  /// Adds [incoming] in order, skipping what is already here.
  ChannelLog merge(List<ChatMessage> incoming) {
    if (incoming.isEmpty) {
      return this;
    }
    final next = [...messages];
    final at = {for (var i = 0; i < next.length; i++) next[i].id: i};
    var changed = false;
    for (final message in incoming) {
      final i = at[message.id];
      if (i == null) {
        at[message.id] = next.length;
        next.add(message);
        changed = true;
      } else if (message.mine && !next[i].mine) {
        next[i] = message;
        changed = true;
      }
    }
    if (!changed) {
      return this;
    }
    final kept = next.length > capacity
        ? next.sublist(next.length - capacity)
        : next;
    return ChannelLog._(List.unmodifiable(kept));
  }

  /// Whether [other] would show the same thing: the same messages in the
  /// same order, said by the same author, with the same own-message marks.
  /// A re-read that changes nothing is not a change to show.
  bool showsSameAs(ChannelLog other) {
    if (identical(this, other)) {
      return true;
    }
    if (messages.length != other.messages.length) {
      return false;
    }
    for (var i = 0; i < messages.length; i++) {
      final a = messages[i];
      final b = other.messages[i];
      if (a.id != b.id ||
          a.mine != b.mine ||
          a.author != b.author ||
          a.body != b.body ||
          a.hidden != b.hidden ||
          a.verifiedResident != b.verifiedResident) {
        return false;
      }
    }
    return true;
  }

  /// Marks the messages whose ids are in [ids] as the reader's own.
  ChannelLog markMine(Set<String> ids) {
    if (!messages.any((m) => !m.mine && ids.contains(m.id))) {
      return this;
    }
    return ChannelLog._(
      List.unmodifiable([
        for (final m in messages)
          !m.mine && ids.contains(m.id) ? m.asMine() : m,
      ]),
    );
  }
}
