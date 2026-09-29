import Flutter
import Foundation
import UIKit

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// The bridge to Apple Foundation Models (iOS 26+), on the device.
///
/// Channel `democracy/on_device_ai`:
/// - `availability` → `{status: available|unavailable, reason?, model?}`
/// - `prepare` → nil (iOS downloads the model itself; there is nothing to ask)
/// - `generate` `{task, instructions, prompt}` → the output as a JSON string
///
/// Event channel `democracy/on_device_ai/stream` takes the same arguments and
/// sends growing JSON snapshots, then ends.
///
/// Each task has a `@Generable` output type, so the model is constrained to
/// the shape the app validates, and sampling is greedy, so the same input
/// gives the same answer. Nothing leaves the device: there is no network call
/// here and no key.
final class OnDeviceAiPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let channelName = "democracy/on_device_ai"
  static let streamChannelName = "democracy/on_device_ai/stream"

  private var streamTask: Task<Void, Never>?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OnDeviceAiPlugin()
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(
      name: streamChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result(Self.availability())
    case "prepare":
      result(nil)
    case "generate":
      guard let request = OnDeviceRequest(call.arguments) else {
        result(FlutterError(code: "failed", message: "bad arguments", details: nil))
        return
      }
      #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
          Task {
            do {
              let json = try await OnDeviceGenerator.generate(request)
              await MainActor.run { result(json) }
            } catch {
              let failure = OnDeviceGenerator.flutterError(error)
              await MainActor.run { result(failure) }
            }
          }
          return
        }
      #endif
      result(FlutterError(code: "unavailable", message: "osTooOld", details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard let request = OnDeviceRequest(arguments) else {
      return FlutterError(code: "failed", message: "bad arguments", details: nil)
    }
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        streamTask?.cancel()
        streamTask = Task {
          do {
            try await OnDeviceGenerator.stream(request) { snapshot in
              await MainActor.run { events(snapshot) }
            }
            await MainActor.run { events(FlutterEndOfEventStream) }
          } catch is CancellationError {
            // The listener went away; nobody is waiting for an answer.
          } catch {
            let failure = OnDeviceGenerator.flutterError(error)
            await MainActor.run {
              events(failure)
              events(FlutterEndOfEventStream)
            }
          }
        }
        return nil
      }
    #endif
    return FlutterError(code: "unavailable", message: "osTooOld", details: nil)
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    streamTask?.cancel()
    streamTask = nil
    return nil
  }

  /// Whether the system model can run here, and which one it is.
  static func availability() -> [String: Any] {
    func unavailable(_ reason: String) -> [String: Any] {
      ["status": "unavailable", "reason": reason]
    }
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
          // The app's text is Korean; a model that cannot read it would
          // answer anyway, and badly.
          guard model.supportsLocale(Locale(identifier: "ko_KR")) else {
            return unavailable("unsupportedLanguage")
          }
          return ["status": "available", "model": modelVersion()]
        case .unavailable(let reason):
          switch reason {
          case .deviceNotEligible:
            return unavailable("deviceNotEligible")
          case .appleIntelligenceNotEnabled:
            return unavailable("appleIntelligenceNotEnabled")
          case .modelNotReady:
            return unavailable("modelNotReady")
          @unknown default:
            return unavailable("deviceNotEligible")
          }
        }
      }
    #endif
    return unavailable("osTooOld")
  }

  /// The model ships with the OS, so the OS build names it. Part of the
  /// app's cache key: an update that changes the model changes the answer.
  static func modelVersion() -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersionString
      .replacingOccurrences(of: " ", with: "")
    return "apple-foundation-models/ios-\(os)"
  }
}

/// `{task, instructions, prompt}` from Dart.
struct OnDeviceRequest {
  let task: String
  let instructions: String
  let prompt: String

  init?(_ arguments: Any?) {
    guard let map = arguments as? [String: Any],
      let task = map["task"] as? String,
      let instructions = map["instructions"] as? String,
      let prompt = map["prompt"] as? String
    else { return nil }
    self.task = task
    self.instructions = instructions
    self.prompt = prompt
  }
}

#if canImport(FoundationModels)

  // MARK: - Output shapes. Property names are the JSON keys the app reads.

  @available(iOS 26.0, *)
  @Generable
  struct MatchOutput {
    @Guide(description: "관심 분야마다 하나씩")
    var axes: [MatchAxisOutput]
  }

  @available(iOS 26.0, *)
  @Generable
  struct MatchAxisOutput {
    @Guide(description: "관심 분야 이름. 입력에 적힌 그대로")
    var label: String
    @Guide(description: "그 분야를 직접 다루는 공약·법안이 얼마나 있는지. 없으면 0", .range(0...100))
    var score: Int
    @Guide(description: "근거. 입력 항목 하나씩", .maximumCount(2))
    var reasons: [MatchReasonOutput]
  }

  @available(iOS 26.0, *)
  @Generable
  struct MatchReasonOutput {
    @Guide(description: "근거로 든 입력 항목의 번호. 예: P3, B2")
    var id: String
    @Guide(description: "그 항목이 이 분야와 어떻게 관련되는지 60자 이내 한 문장. 사실만")
    var text: String
  }

  @available(iOS 26.0, *)
  @Generable
  struct StanceOutput {
    @Guide(description: "공약마다 하나씩")
    var items: [StanceItem]
  }

  @available(iOS 26.0, *)
  @Generable
  struct StanceItem {
    @Guide(description: "공약 번호. 예: P1")
    var id: String
    @Guide(description: "성장·투자 확대 -1, 소득 재분배·복지 확대 1, 둘 다 아니면 0", .range(-1...1))
    var x: Int
    @Guide(description: "규제 신설·공공 관리 강화 -1, 규제 완화·민간 자율 1, 둘 다 아니면 0", .range(-1...1))
    var y: Int
  }

  @available(iOS 26.0, *)
  @Generable
  struct IssueOutput {
    @Guide(description: "제목마다 하나씩")
    var items: [IssueItem]
  }

  @available(iOS 26.0, *)
  @Generable
  struct IssueItem {
    @Guide(description: "제목 번호. 예: I1")
    var id: String
    @Guide(
      description: "제목이 주로 다루는 쟁점",
      .anyOf([
        "주거·부동산", "교통", "교육·보육", "복지·돌봄", "보건·의료", "일자리·경제",
        "안전·재난", "환경·에너지", "문화·체육", "행정·제도", "기타",
      ]))
    var label: String
  }

  // MARK: - Running

  @available(iOS 26.0, *)
  enum OnDeviceGenerator {
    /// Greedy: the same input gives the same answer, so a cached answer and
    /// a fresh one agree.
    static var options: GenerationOptions { GenerationOptions(samplingMode: .greedy) }

    static func session(_ request: OnDeviceRequest) -> LanguageModelSession {
      LanguageModelSession(model: .default, instructions: request.instructions)
    }

    static func generate(_ request: OnDeviceRequest) async throws -> String {
      switch request.task {
      case "match": return try await respond(MatchOutput.self, request)
      case "stances": return try await respond(StanceOutput.self, request)
      case "issues": return try await respond(IssueOutput.self, request)
      default: throw OnDeviceBridgeError.unknownTask
      }
    }

    static func stream(
      _ request: OnDeviceRequest, emit: @escaping (String) async -> Void
    ) async throws {
      switch request.task {
      case "match": try await stream(MatchOutput.self, request, emit: emit)
      case "stances": try await stream(StanceOutput.self, request, emit: emit)
      case "issues": try await stream(IssueOutput.self, request, emit: emit)
      default: throw OnDeviceBridgeError.unknownTask
      }
    }

    private static func respond<Output: Generable>(
      _ type: Output.Type, _ request: OnDeviceRequest
    ) async throws -> String {
      let response = try await session(request).respond(
        to: request.prompt, generating: type, options: options)
      return response.rawContent.jsonString
    }

    private static func stream<Output: Generable>(
      _ type: Output.Type, _ request: OnDeviceRequest, emit: @escaping (String) async -> Void
    ) async throws {
      let stream = session(request).streamResponse(
        to: request.prompt, generating: type, options: options)
      for try await snapshot in stream {
        try Task.checkCancellation()
        await emit(snapshot.rawContent.jsonString)
      }
    }

    /// A failure, in the codes the app reads (`OnDeviceModelException.code`),
    /// or `unavailable` with the reason for one that means the model cannot
    /// run here at all.
    static func flutterError(_ error: Error) -> FlutterError {
      let (code, message) = classify(error)
      return FlutterError(code: code, message: message ?? String(describing: error), details: nil)
    }

    static func classify(_ error: Error) -> (String, String?) {
      if error is OnDeviceBridgeError { return ("failed", "unknown task") }
      if #available(iOS 27.0, *) {
        if let failure = error as? LanguageModelError {
          switch failure {
          case .contextSizeExceeded: return ("context", nil)
          case .rateLimited, .timeout: return ("busy", nil)
          case .guardrailViolation, .refusal: return ("guardrail", nil)
          case .unsupportedLanguageOrLocale: return ("unavailable", "unsupportedLanguage")
          default: return ("failed", nil)
          }
        }
        if let failure = error as? SystemLanguageModel.Error,
          case .assetsUnavailable = failure
        {
          return ("unavailable", "modelNotReady")
        }
        if let failure = error as? LanguageModelSession.Error,
          case .concurrentRequests = failure
        {
          return ("busy", nil)
        }
      }
      if let failure = error as? LanguageModelSession.GenerationError {
        switch failure {
        case .exceededContextWindowSize: return ("context", nil)
        case .assetsUnavailable: return ("unavailable", "modelNotReady")
        case .guardrailViolation, .refusal: return ("guardrail", nil)
        case .unsupportedLanguageOrLocale: return ("unavailable", "unsupportedLanguage")
        case .rateLimited, .concurrentRequests: return ("busy", nil)
        case .decodingFailure, .unsupportedGuide: return ("output", nil)
        @unknown default: return ("failed", nil)
        }
      }
      return ("failed", nil)
    }
  }

  enum OnDeviceBridgeError: Error {
    case unknownTask
  }

#endif
