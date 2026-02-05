package com.example.clipforge

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.clipforge/video_split"
    private val PROGRESS_CHANNEL = "com.clipforge/video_split/progress"
    private val LOCAL_WHISPER_CHANNEL = "com.clipforge/local_whisper"
    private val LOCAL_WHISPER_PROGRESS_CHANNEL = "com.clipforge/local_whisper/progress"
    
    private var videoSplitHandler: VideoSplitHandler? = null
    private var localWhisperHandler: LocalWhisperHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        videoSplitHandler = VideoSplitHandler(this)
        localWhisperHandler = LocalWhisperHandler(this)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "splitAndExport" -> {
                    val args = call.arguments as? HashMap<String, Any>
                    if (args != null) {
                        videoSplitHandler?.splitAndExport(args, result)
                    } else {
                        result.error("INVALID_ARGS", "Arguments required", null)
                    }
                }
                "getVideoDuration" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        videoSplitHandler?.getVideoDuration(path, result)
                    } else {
                        result.error("INVALID_PATH", "Video path required", null)
                    }
                }
                "cancelExport" -> {
                    videoSplitHandler?.cancelExport()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCAL_WHISPER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "transcribeAudioLocal" -> {
                        val audioPath = call.argument<String>("audioPath")
                        if (audioPath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "audioPath is required", null)
                        } else {
                            localWhisperHandler?.transcribeAudioToSrt(audioPath, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_WHISPER_PROGRESS_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    localWhisperHandler?.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    localWhisperHandler?.setEventSink(null)
                }
            }
        )
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    videoSplitHandler?.setEventSink(events)
                }
                
                override fun onCancel(arguments: Any?) {
                    videoSplitHandler?.setEventSink(null)
                }
            }
        )
    }
    
    override fun onDestroy() {
        videoSplitHandler?.cleanup()
        localWhisperHandler?.cleanup()
        super.onDestroy()
    }
}
