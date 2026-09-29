package com.democracy.kr.democracy

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The Android half of `democracy/on_device_ai`: Gemini Nano through the ML Kit
 * GenAI Prompt API, on the device (AICore). No network call, no key.
 *
 * - `availability` → `{status: available|unavailable, reason?, model?}`
 * - `prepare` → null, after asking AICore to download the model if it can
 * - `generate` `{task, instructions, prompt}` → the model's JSON answer
 *
 * The event channel `democracy/on_device_ai/stream` sends the answer so far
 * (accumulated text) as it grows, then ends.
 *
 * ML Kit's GenAI libraries need API 26; this app still installs on 24. Every
 * ML Kit type lives in [GeminiNanoBridge], which is only created on 26+, so
 * an older device answers `osTooOld` without loading any of it.
 */
class OnDeviceAiPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var channel: MethodChannel? = null
    private var events: EventChannel? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var streamJob: Job? = null

    private val bridge: GeminiNanoBridge? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) GeminiNanoBridge() else null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, STREAM_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        channel = null
        events = null
        scope.cancel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) bridge?.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> scope.launch {
                result.success(bridge?.availability() ?: unavailable("osTooOld"))
            }

            "prepare" -> {
                bridge?.let { b -> scope.launch { b.download() } }
                result.success(null)
            }

            "generate" -> {
                val request = OnDeviceRequest.from(call.arguments)
                val b = bridge
                if (request == null) {
                    result.error("failed", "bad arguments", null)
                    return
                }
                if (b == null) {
                    result.error("unavailable", "osTooOld", null)
                    return
                }
                scope.launch {
                    try {
                        result.success(b.generate(request))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        val (code, message) = b.classify(e)
                        result.error(code, message, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        val request = OnDeviceRequest.from(arguments)
        val b = bridge
        if (request == null) {
            sink.error("failed", "bad arguments", null)
            sink.endOfStream()
            return
        }
        if (b == null) {
            sink.error("unavailable", "osTooOld", null)
            sink.endOfStream()
            return
        }
        streamJob?.cancel()
        streamJob = scope.launch {
            try {
                b.stream(request) { snapshot -> sink.success(snapshot) }
                sink.endOfStream()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val (code, message) = b.classify(e)
                sink.error(code, message, null)
                sink.endOfStream()
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        streamJob?.cancel()
        streamJob = null
    }

    companion object {
        const val CHANNEL = "democracy/on_device_ai"
        const val STREAM_CHANNEL = "democracy/on_device_ai/stream"

        fun unavailable(reason: String): Map<String, Any> =
            mapOf("status" to "unavailable", "reason" to reason)
    }
}

/** `{task, instructions, prompt}` from Dart. */
data class OnDeviceRequest(val task: String, val instructions: String, val prompt: String) {
    companion object {
        fun from(arguments: Any?): OnDeviceRequest? {
            val map = arguments as? Map<*, *> ?: return null
            val task = map["task"] as? String ?: return null
            val instructions = map["instructions"] as? String ?: return null
            val prompt = map["prompt"] as? String ?: return null
            return OnDeviceRequest(task, instructions, prompt)
        }
    }
}
