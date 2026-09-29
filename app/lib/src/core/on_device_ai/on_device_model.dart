/// The model on the reader's own device, and what it can say about itself.
///
/// Every AI figure in a live build comes from here: Apple Foundation Models on
/// iOS 26+, Gemini Nano through ML Kit on Android. Nothing is sent to a model
/// server, no key is involved, and nothing the model produces leaves the
/// device. When the model cannot run, the screen says why in words and draws
/// nothing -- never a fixture, never a sample.
library;

/// Why the on-device model cannot run here.
///
/// Each reason has the short phrase the screen prints after
/// 「이 기기에서는 온디바이스 AI를 쓸 수 없습니다」, so a reader can tell a
/// setting they can change from a device that will never support it.
enum ModelUnavailableReason {
  /// The hardware or OS build has no on-device model at all.
  deviceNotEligible('지원 기기 아님', '이 기기는 온디바이스 AI 모델을 지원하지 않습니다.'),

  /// iOS: the device can run it, but Apple Intelligence is switched off.
  appleIntelligenceNotEnabled(
    'Apple Intelligence 꺼짐',
    '설정 > Apple Intelligence 및 Siri에서 켜면 쓸 수 있습니다.',
  ),

  /// The model is still being downloaded or set up by the system.
  modelNotReady('모델 준비 중', '시스템이 모델을 내려받거나 준비하고 있습니다. 잠시 후 다시 열어 주세요.'),

  /// Android: the model can be downloaded but has not been yet.
  modelDownloadable('모델 준비 중', '기기 모델을 아직 내려받지 않았습니다. 내려받은 뒤 이 기기에서 분석합니다.'),

  /// The model on this device cannot read Korean.
  unsupportedLanguage('한국어 미지원', '이 기기의 모델이 한국어를 지원하지 않습니다.'),

  /// The OS is older than the first one with an on-device model API.
  osTooOld('OS 버전 미지원', 'iOS 26 또는 온디바이스 모델을 지원하는 Android 버전이 필요합니다.'),

  /// A platform with no bridge at all (desktop, web, tests).
  unsupportedPlatform('지원 기기 아님', '이 플랫폼에는 온디바이스 AI가 없습니다.');

  const ModelUnavailableReason(this.label, this.detail);

  /// Two or three words, set after the headline.
  final String label;

  /// One sentence of what to do about it, if anything.
  final String detail;

  static ModelUnavailableReason parse(Object? raw) {
    for (final reason in values) {
      if (reason.name == raw) {
        return reason;
      }
    }
    return deviceNotEligible;
  }
}

/// Whether the model can run, and if so which one it is.
sealed class ModelAvailability {
  const ModelAvailability();

  /// Reads the bridge's `{status, reason, model}` answer.
  factory ModelAvailability.fromMap(Object? raw) {
    if (raw is! Map) {
      return const ModelUnavailable(ModelUnavailableReason.deviceNotEligible);
    }
    final model = raw['model'];
    if (raw['status'] == 'available' && model is String && model.isNotEmpty) {
      return ModelAvailable(model);
    }
    return ModelUnavailable(ModelUnavailableReason.parse(raw['reason']));
  }
}

final class ModelAvailable extends ModelAvailability {
  const ModelAvailable(this.modelVersion);

  /// Which model, as precisely as the platform says -- part of every cache
  /// key, so an OS update that changes the model also changes the answer.
  final String modelVersion;
}

final class ModelUnavailable extends ModelAvailability {
  const ModelUnavailable(this.reason);

  final ModelUnavailableReason reason;
}

/// What a run is for. Each has its own output shape on the native side
/// (a `@Generable` struct on iOS), so the task travels with the prompt.
enum OnDeviceTask { match, stances, issues }

/// One call to the model: fixed instructions, the input as text, and the
/// task that says which output shape to generate.
class OnDeviceRequest {
  const OnDeviceRequest({
    required this.task,
    required this.instructions,
    required this.prompt,
  });

  final OnDeviceTask task;
  final String instructions;
  final String prompt;

  Map<String, Object?> toMap() => {
    'task': task.name,
    'instructions': instructions,
    'prompt': prompt,
  };
}

/// The model ran and failed, or ran and said nothing usable.
class OnDeviceModelException implements Exception {
  const OnDeviceModelException(this.code, [this.message = '']);

  /// `guardrail`, `context`, `language`, `busy`, `unavailable`, `output` or
  /// `failed`.
  final String code;
  final String message;

  /// What the screen prints, in one line.
  String get readerMessage => switch (code) {
    'guardrail' => '기기 모델이 이 요청을 처리하지 않았습니다.',
    'context' => '입력이 기기 모델이 한 번에 읽을 수 있는 양을 넘었습니다.',
    'language' => '이 기기의 모델이 한국어를 지원하지 않습니다.',
    'busy' => '기기 모델이 다른 작업 중입니다. 잠시 후 다시 시도해 주세요.',
    'output' => '기기 모델의 답을 검증하지 못했습니다.',
    _ => '기기 모델이 분석을 끝내지 못했습니다.',
  };

  @override
  String toString() => 'OnDeviceModelException($code): $message';
}

/// Raised in place of any AI output when the model cannot run here.
///
/// A screen catches this and says 「이 기기에서는 온디바이스 AI를 쓸 수
/// 없습니다」 with [reason] -- the honest state, instead of 준비 중 (which
/// would promise it is coming) or a sample (which would be made up).
class OnDeviceUnavailableException implements Exception {
  const OnDeviceUnavailableException(this.reason);

  final ModelUnavailableReason reason;

  @override
  String toString() => 'OnDeviceUnavailableException(${reason.name})';
}

/// The model, as the app sees it.
///
/// [generate] answers with the model's structured output as a JSON string;
/// [stream] answers with growing snapshots of it (on iOS each is a valid
/// partial object, on Android raw text that parses only at the end). Both
/// use deterministic sampling, so the same input gives the same answer.
abstract interface class OnDeviceModel {
  Future<ModelAvailability> availability();

  /// Asks the system to fetch the model, where the platform lets an app ask
  /// (Android). A no-op elsewhere.
  Future<void> prepare();

  Future<String> generate(OnDeviceRequest request);

  Stream<String> stream(OnDeviceRequest request);
}

/// A device with no model: every question answers with [reason].
class UnavailableOnDeviceModel implements OnDeviceModel {
  const UnavailableOnDeviceModel([
    this.reason = ModelUnavailableReason.unsupportedPlatform,
  ]);

  final ModelUnavailableReason reason;

  @override
  Future<ModelAvailability> availability() async => ModelUnavailable(reason);

  @override
  Future<void> prepare() async {}

  @override
  Future<String> generate(OnDeviceRequest request) =>
      Future.error(OnDeviceUnavailableException(reason));

  @override
  Stream<String> stream(OnDeviceRequest request) =>
      Stream.error(OnDeviceUnavailableException(reason));
}
