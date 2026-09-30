package com.democracy.kr.democracy

import android.os.Build
import androidx.annotation.RequiresApi
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest

/**
 * Gemini Nano through ML Kit's Prompt API. Only ever created on API 26+.
 *
 * There is no schema-constrained output on this path (the typed request is
 * still alpha), so the prompt asks for JSON and the app validates whatever
 * comes back: unknown ids, labels and out-of-range numbers are dropped there,
 * not trusted here. Sampling is pinned (temperature 0, top-k 1, seed 0) so
 * the same input gives the same answer.
 */
@RequiresApi(Build.VERSION_CODES.O)
class GeminiNanoBridge {

    private val model: GenerativeModel by lazy { Generation.getClient() }

    suspend fun availability(): Map<String, Any> {
        return try {
            when (model.checkStatus()) {
                FeatureStatus.AVAILABLE -> {
                    val name = runCatching { model.getBaseModelName() }.getOrNull()
                    mapOf(
                        "status" to "available",
                        "model" to "gemini-nano/${name ?: "unknown"}/${Build.VERSION.INCREMENTAL}",
                    )
                }

                // The device supports it but has not fetched it; the app can
                // ask for the download (prepare).
                FeatureStatus.DOWNLOADABLE -> OnDeviceAiPlugin.unavailable("modelDownloadable")
                FeatureStatus.DOWNLOADING -> OnDeviceAiPlugin.unavailable("modelNotReady")
                else -> OnDeviceAiPlugin.unavailable("deviceNotEligible")
            }
        } catch (e: GenAiException) {
            OnDeviceAiPlugin.unavailable(
                when (e.errorCode) {
                    GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE -> "osTooOld"
                    GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE -> "modelNotReady"
                    else -> "deviceNotEligible"
                },
            )
        } catch (e: Exception) {
            // No AICore at all, or a device ML Kit does not know.
            OnDeviceAiPlugin.unavailable("deviceNotEligible")
        }
    }

    /** Asks AICore to fetch the model. Progress is read back through [availability]. */
    suspend fun download() {
        runCatching { model.download().collect { } }
    }

    private suspend fun request(request: OnDeviceRequest): GenerateContentRequest {
        val system = runCatching { model.isSystemPromptAvailable() }.getOrDefault(false)
        val configure: GenerateContentRequest.Builder.() -> Unit = {
            temperature = 0f
            topK = 1
            seed = 0
            candidateCount = 1
        }
        return if (system) {
            generateContentRequest(
                SystemInstruction(request.instructions),
                TextPart(request.fullPrompt),
                configure,
            )
        } else {
            generateContentRequest(
                TextPart("${request.instructions}\n\n${request.fullPrompt}"),
                configure,
            )
        }
    }

    suspend fun generate(request: OnDeviceRequest): String {
        val response = model.generateContent(request(request))
        val text = response.candidates.firstOrNull()?.text
        if (text.isNullOrBlank()) throw EmptyAnswer()
        return text
    }

    /** Sends the accumulated answer after each chunk. */
    suspend fun stream(request: OnDeviceRequest, emit: (String) -> Unit) {
        val answer = StringBuilder()
        model.generateContentStream(request(request)).collect { chunk ->
            val piece = chunk.candidates.firstOrNull()?.text ?: return@collect
            answer.append(piece)
            emit(answer.toString())
        }
        if (answer.isBlank()) throw EmptyAnswer()
    }

    fun close() {
        runCatching { model.close() }
    }

    /** A failure in the codes the app reads (`OnDeviceModelException.code`). */
    fun classify(error: Throwable): Pair<String, String?> {
        if (error is EmptyAnswer) return "output" to "empty answer"
        if (error !is GenAiException) return "failed" to error.javaClass.simpleName
        return when (error.errorCode) {
            GenAiException.ErrorCode.BUSY,
            GenAiException.ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED,
            GenAiException.ErrorCode.BACKGROUND_USE_BLOCKED -> "busy" to null

            GenAiException.ErrorCode.REQUEST_TOO_LARGE -> "context" to null
            GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE -> "unavailable" to "osTooOld"
            GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE -> "unavailable" to "modelNotReady"
            GenAiException.ErrorCode.NOT_AVAILABLE,
            GenAiException.ErrorCode.NOT_SUPPORTED,
            GenAiException.ErrorCode.AICORE_INCOMPATIBLE -> "unavailable" to "deviceNotEligible"

            GenAiException.ErrorCode.RESPONSE_PROCESSING_ERROR,
            GenAiException.ErrorCode.RESPONSE_GENERATION_ERROR -> "output" to null

            else -> "failed" to "GenAiException ${error.errorCode}"
        }
    }

    private class EmptyAnswer : Exception()
}
