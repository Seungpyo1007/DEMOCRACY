import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device's model. None by default -- fixture builds, tests and goldens
/// never reach a model; a live build overrides this with the platform bridge.
final onDeviceModelProvider = Provider<OnDeviceModel>(
  (ref) => const UnavailableOnDeviceModel(),
);
