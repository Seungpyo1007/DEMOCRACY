package com.democracy.kr.democracy

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// A fragment activity because local_auth shows the system biometric prompt,
// which needs one.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The on-device model bridge (Gemini Nano via ML Kit). App code, not
        // a package, so it is added by hand beside the generated plugins.
        flutterEngine.plugins.add(OnDeviceAiPlugin())
    }
}
