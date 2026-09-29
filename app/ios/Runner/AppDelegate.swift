import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The on-device model bridge (Apple Foundation Models). App code, not a
    // package, so it is registered by hand beside the generated ones.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceAiPlugin") {
      OnDeviceAiPlugin.register(with: registrar)
    }
  }
}
