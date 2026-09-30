import 'dart:async';

import 'package:democracy/src/features/reviews/data/live_channel.dart';
import 'package:realtime_client/realtime_client.dart';

/// District channel broadcasts over Supabase Realtime.
///
/// The server sends them from the database (a trigger on the channel's
/// table, `realtime.send`) on the public topic `district-chat:<id>`, so
/// joining needs only the project's anon key, which the build already has
/// for the BFF. No user token goes on the socket: the channel is readable by
/// anyone, and a signed-out reader should see it move too.
///
/// Each link is its own socket, closed with the link. Reconnecting is left
/// to [LiveChannel], which re-reads the channel after every join; letting the
/// client rejoin on its own would skip that read and lose what was said
/// while the socket was down.
class RealtimeChannelTransport implements ChannelTransport {
  RealtimeChannelTransport({required Uri projectUrl, required this.anonKey})
    : endpoint = realtimeEndpoint(projectUrl);

  /// `https://<ref>.supabase.co` → `wss://<ref>.supabase.co/realtime/v1`.
  static String realtimeEndpoint(Uri projectUrl) => Uri(
    scheme: projectUrl.scheme == 'http' ? 'ws' : 'wss',
    host: projectUrl.host,
    port: projectUrl.hasPort ? projectUrl.port : null,
    path: '/realtime/v1',
  ).toString();

  final String endpoint;
  final String anonKey;

  /// The two events the trigger sends.
  static const events = ['message', 'delete'];

  @override
  ChannelLink join(
    String topic, {
    required void Function(String event, Map<String, Object?> payload) onEvent,
    required void Function(ChannelLinkState state) onState,
  }) {
    final client = RealtimeClient(
      endpoint,
      params: {'apikey': anonKey},
      headers: {'apikey': anonKey},
    );
    final link = _RealtimeLink(client);
    final channel = client.channel(
      topic,
      const RealtimeChannelConfig(private: false),
    );

    for (final event in events) {
      channel.onBroadcast(
        event: event,
        callback: (message) {
          if (!link.closed) {
            onEvent(event, broadcastBody(message));
          }
        },
      );
    }
    channel.subscribe((status, _) {
      if (link.closed) {
        return;
      }
      onState(
        status == RealtimeSubscribeStatus.subscribed
            ? ChannelLinkState.joined
            : ChannelLinkState.failed,
      );
    });
    return link;
  }

  /// A broadcast arrives as `{type, event, payload, ...}`; the message is
  /// the inner payload.
  static Map<String, Object?> broadcastBody(Map<String, dynamic> message) {
    final inner = message['payload'];
    return inner is Map
        ? Map<String, Object?>.from(inner)
        : Map<String, Object?>.from(message);
  }
}

class _RealtimeLink implements ChannelLink {
  _RealtimeLink(this.client);

  final RealtimeClient client;
  bool closed = false;

  /// Closing the socket is enough: the server drops its channels with it,
  /// and a polite leave on a dead socket would only wait out its timeout.
  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await client.disconnect();
  }
}
