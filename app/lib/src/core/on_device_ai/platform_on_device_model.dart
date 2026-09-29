import 'dart:async';

import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:flutter/services.dart';

/// The bridge to the native model: `ios/Runner/OnDeviceAiPlugin.swift` and
/// `android/.../OnDeviceAiPlugin.kt`.
///
/// Methods on [channelName]:
/// - `availability` → `{status: available|unavailable, reason?, model?}`
/// - `prepare` → null (Android starts the model download; iOS does nothing)
/// - `generate` `{task, instructions, prompt}` → the output as a JSON string
///
/// [streamChannelName] takes the same arguments and sends growing snapshots
/// of the output, then closes. Errors arrive as [PlatformException]s whose
/// code is one of [OnDeviceModelException.code]'s values, or `unavailable`
/// with the reason as the message.
class PlatformOnDeviceModel implements OnDeviceModel {
  const PlatformOnDeviceModel({
    this.channel = const MethodChannel(channelName),
    this.streamChannel = const EventChannel(streamChannelName),
  });

  static const channelName = 'democracy/on_device_ai';
  static const streamChannelName = 'democracy/on_device_ai/stream';

  final MethodChannel channel;
  final EventChannel streamChannel;

  @override
  Future<ModelAvailability> availability() async {
    try {
      final raw = await channel.invokeMethod<Object?>('availability');
      return ModelAvailability.fromMap(raw);
    } on MissingPluginException {
      return const ModelUnavailable(ModelUnavailableReason.unsupportedPlatform);
    } on PlatformException {
      return const ModelUnavailable(ModelUnavailableReason.deviceNotEligible);
    }
  }

  @override
  Future<void> prepare() async {
    try {
      await channel.invokeMethod<void>('prepare');
    } on MissingPluginException {
      // Nothing to prepare on a platform with no bridge.
    }
  }

  @override
  Future<String> generate(OnDeviceRequest request) async {
    try {
      final text = await channel.invokeMethod<String>(
        'generate',
        request.toMap(),
      );
      if (text == null || text.trim().isEmpty) {
        throw const OnDeviceModelException('output', 'empty answer');
      }
      return text;
    } on MissingPluginException {
      throw const OnDeviceUnavailableException(
        ModelUnavailableReason.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Stream<String> stream(OnDeviceRequest request) {
    return streamChannel
        .receiveBroadcastStream(request.toMap())
        .map((event) => event is String ? event : '')
        .where((text) => text.isNotEmpty)
        .handleError(
          (Object error) => throw error is PlatformException
              ? _translate(error)
              : error is MissingPluginException
              ? const OnDeviceUnavailableException(
                  ModelUnavailableReason.unsupportedPlatform,
                )
              : error,
        );
  }

  static Exception _translate(PlatformException error) {
    if (error.code == 'unavailable') {
      return OnDeviceUnavailableException(
        ModelUnavailableReason.parse(error.message),
      );
    }
    return OnDeviceModelException(error.code, error.message ?? '');
  }
}
