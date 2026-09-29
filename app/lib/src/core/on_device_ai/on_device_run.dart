/// When and by which model a result was produced on this device.
///
/// Carried by every on-device result so the screen can say
/// 「이 기기에서 생성 · 9월 30일」: the reader should know both that the figure
/// was made by a model and that it was made here, from the text listed under
/// it, and not fetched from a server.
class OnDeviceRun {
  const OnDeviceRun({required this.generatedAt, required this.model});

  final DateTime generatedAt;

  /// The platform's own name for the model, e.g. `apple-foundation-models/…`.
  final String model;
}

/// The line set under every on-device result.
const onDeviceLabel = '이 기기에서 생성';
