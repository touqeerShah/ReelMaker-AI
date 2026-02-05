package com.example.clipforge

import android.content.Context
import android.util.Log
import com.whispercpp.whisper.WhisperContext
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val TAG = "LocalWhisperHandler"

class LocalWhisperHandler(private val context: Context) {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var whisperContext: WhisperContext? = null
    private var loadedModelPath: String? = null
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    private fun emitProgress(
        stage: String,
        processedChunks: Int? = null,
        totalChunks: Int? = null,
        message: String? = null,
    ) {
        val payload = hashMapOf<String, Any>(
            "stage" to stage,
            "timestamp" to System.currentTimeMillis(),
        )
        if (processedChunks != null) payload["processedChunks"] = processedChunks
        if (totalChunks != null) payload["totalChunks"] = totalChunks
        if (message != null) payload["message"] = message
        scope.launch(Dispatchers.Main) {
            eventSink?.success(payload)
        }
    }

    fun transcribeAudioToSrt(audioPath: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                emitProgress(stage = "loading_model", message = "Loading local whisper model")
                val srt = withContext(Dispatchers.IO) {
                    val modelPath = ensureModelPath()
                    ensureWhisperContext(modelPath)
                    transcribeWaveInChunksToSrt(File(audioPath))
                }
                emitProgress(stage = "done", message = "Audio to text completed")
                result.success(srt)
            } catch (e: Throwable) {
                Log.e(TAG, "Local whisper transcription failed", e)
                emitProgress(stage = "failed", message = e.message ?: "Local whisper failed")
                result.error("LOCAL_WHISPER_FAILED", e.message, null)
            }
        }
    }

    fun cleanup() {
        scope.launch {
            try {
                withContext(Dispatchers.IO) { whisperContext?.release() }
            } catch (_: Exception) {
            } finally {
                whisperContext = null
                loadedModelPath = null
            }
        }
        scope.cancel()
    }

    private fun ensureModelPath(): String {
        val modelDir = File(context.filesDir, "models")
        if (!modelDir.exists()) modelDir.mkdirs()
        val modelFile = File(modelDir, "ggml-base.bin")
        if (!modelFile.exists()) {
            val candidates = listOf(
                "models/ggml-base.bin", // expected path
                "ggml-base.bin", // when models dir is mounted as asset root
            )

            var copied = false
            var lastError: Exception? = null
            for (assetPath in candidates) {
                try {
                    context.assets.open(assetPath).use { input ->
                        modelFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    copied = true
                    Log.i(TAG, "Loaded whisper model asset from: $assetPath")
                    break
                } catch (e: Exception) {
                    lastError = e
                }
            }

            if (!copied) {
                val rootAssets = context.assets.list("")?.joinToString(", ") ?: "none"
                val modelAssets = context.assets.list("models")?.joinToString(", ") ?: "none"
                throw IllegalStateException(
                    "Whisper model asset not found. Tried: ${candidates.joinToString(", ")}. " +
                        "Root assets: [$rootAssets], models/: [$modelAssets]. " +
                        "Last error: ${lastError?.message}"
                )
            }
        }
        return modelFile.absolutePath
    }

    private fun ensureWhisperContext(modelPath: String) {
        if (whisperContext != null && loadedModelPath == modelPath) return
        whisperContext?.let {
            runCatching {
                kotlinx.coroutines.runBlocking { it.release() }
            }
        }
        whisperContext = WhisperContext.createContextFromFile(modelPath)
        loadedModelPath = modelPath
    }

    private data class WavMeta(
        val channels: Int,
        val sampleRate: Int,
        val dataOffset: Int = 44,
        val bytesPerSampleAllChannels: Int,
    )

    private fun readWavMeta(file: File): WavMeta {
        val header = ByteArray(44)
        FileInputStream(file).use { fis ->
            val read = fis.read(header)
            if (read < 44) throw IllegalStateException("Invalid WAV header")
        }
        val bb = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val channels = bb.getShort(22).toInt().coerceAtLeast(1)
        val sampleRate = bb.getInt(24).coerceAtLeast(16000)
        val bitsPerSample = bb.getShort(34).toInt().coerceAtLeast(16)
        if (bitsPerSample != 16) {
            throw IllegalStateException("Only PCM16 WAV is supported, got $bitsPerSample-bit")
        }
        return WavMeta(
            channels = channels,
            sampleRate = sampleRate,
            bytesPerSampleAllChannels = channels * 2,
        )
    }

    private suspend fun transcribeWaveInChunksToSrt(file: File): String {
        val meta = readWavMeta(file)
        val chunkSeconds = 30
        val samplesPerChunk = meta.sampleRate * chunkSeconds
        val chunkBytes = samplesPerChunk * meta.bytesPerSampleAllChannels
        val dataBytes = (file.length() - meta.dataOffset).coerceAtLeast(0L)
        val totalChunks = ((dataBytes + chunkBytes - 1) / chunkBytes).toInt().coerceAtLeast(1)
        emitProgress(
            stage = "transcribing",
            processedChunks = 0,
            totalChunks = totalChunks,
            message = "Starting audio to text"
        )

        val srt = StringBuilder()
        var srtIndex = 1
        var chunkIndex = 0

        FileInputStream(file).use { fis ->
            var skipped = 0L
            while (skipped < meta.dataOffset) {
                val n = fis.skip((meta.dataOffset - skipped).toLong())
                if (n <= 0) break
                skipped += n
            }

            val buf = ByteArray(chunkBytes)
            while (true) {
                val read = fis.read(buf)
                if (read <= 0) break
                val chunkData = if (read == buf.size) buf else buf.copyOf(read)
                val samples = pcm16ToFloatMono(chunkData, meta.channels)
                if (samples.isEmpty()) continue

                emitProgress(
                    stage = "transcribing",
                    processedChunks = chunkIndex,
                    totalChunks = totalChunks,
                    message = "Convert audio to text chunk ${chunkIndex + 1}/$totalChunks (running)"
                )

                val raw = whisperContext?.transcribeData(samples, true)
                    ?: throw IllegalStateException("Whisper context unavailable")
                val offsetSec = chunkIndex * chunkSeconds.toDouble()
                srtIndex = appendChunkAsSrt(raw, offsetSec, srtIndex, srt)
                chunkIndex++
                emitProgress(
                    stage = "transcribing",
                    processedChunks = chunkIndex,
                    totalChunks = totalChunks,
                    message = "Convert audio to text chunk $chunkIndex/$totalChunks"
                )
            }
        }

        if (srt.isEmpty()) {
            throw IllegalStateException("Local whisper returned no timestamped segments")
        }
        return srt.toString()
    }

    private fun pcm16ToFloatMono(bytes: ByteArray, channels: Int): FloatArray {
        if (bytes.isEmpty()) return floatArrayOf()
        val sampleCountAllChannels = bytes.size / 2
        val frameCount = sampleCountAllChannels / channels
        val out = FloatArray(frameCount)

        var byteIndex = 0
        for (i in 0 until frameCount) {
            if (channels == 1) {
                val lo = bytes[byteIndex].toInt() and 0xFF
                val hi = bytes[byteIndex + 1].toInt()
                val s = (hi shl 8) or lo
                out[i] = (s / 32767.0f).coerceIn(-1f, 1f)
                byteIndex += 2
            } else {
                var acc = 0f
                for (c in 0 until channels) {
                    val lo = bytes[byteIndex].toInt() and 0xFF
                    val hi = bytes[byteIndex + 1].toInt()
                    val s = (hi shl 8) or lo
                    acc += (s / 32767.0f)
                    byteIndex += 2
                }
                out[i] = (acc / channels).coerceIn(-1f, 1f)
            }
        }
        return out
    }

    private fun appendChunkAsSrt(
        raw: String,
        offsetSec: Double,
        startIndex: Int,
        out: StringBuilder,
    ): Int {
        val lines = raw.lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && it.startsWith("[") && it.contains(" --> ") }

        var idx = startIndex
        for (line in lines) {
            val sepIndex = line.indexOf("]:")
            if (sepIndex <= 0) continue
            val tsPart = line.substring(1, sepIndex).trim() // 00:00:00.000 --> 00:00:01.230
            val textPart = line.substring(sepIndex + 2).trim()
            val parts = tsPart.split("-->")
            if (parts.size != 2 || textPart.isEmpty()) continue

            val startSec = parseTimeToSec(parts[0].trim()) + offsetSec
            val endSec = parseTimeToSec(parts[1].trim()) + offsetSec
            out.append(idx).append('\n')
            out.append(formatSrtTime(startSec))
                .append(" --> ")
                .append(formatSrtTime(endSec))
                .append('\n')
            out.append(textPart).append("\n\n")
            idx++
        }
        return idx
    }

    private fun parseTimeToSec(ts: String): Double {
        // hh:mm:ss.mmm
        val p = ts.split(":")
        if (p.size != 3) return 0.0
        val h = p[0].toIntOrNull() ?: 0
        val m = p[1].toIntOrNull() ?: 0
        val s = p[2].toDoubleOrNull() ?: 0.0
        return h * 3600 + m * 60 + s
    }

    private fun formatSrtTime(secInput: Double): String {
        val totalMs = (secInput * 1000).toLong().coerceAtLeast(0)
        val h = totalMs / 3600000
        val m = (totalMs % 3600000) / 60000
        val s = (totalMs % 60000) / 1000
        val ms = totalMs % 1000
        return String.format("%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
