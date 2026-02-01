import 'dart:async';
import 'package:flutter/services.dart';
import '../models/split_mode.dart';
import '../models/export_progress.dart';

/// Service for splitting videos with native platform integration
class VideoSplitService {
  static const MethodChannel _channel = MethodChannel('com.clipforge/video_split');
  static const EventChannel _progressChannel = EventChannel('com.clipforge/video_split/progress');
  
  static final VideoSplitService _instance = VideoSplitService._internal();
  factory VideoSplitService() => _instance;
  VideoSplitService._internal();

  Stream<ExportProgress>? _progressStream;

  /// Get stream of export progress events
  Stream<ExportProgress> get progressStream {
    _progressStream ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) => ExportProgress.fromMap(event as Map));
    return _progressStream!;
  }

  /// Split video into segments and export with overlays
  /// 
  /// Returns list of output file paths
  Future<List<String>> splitAndExport({
    required String inputPath,
    required SplitMode mode,
    required int segmentSeconds,
    required int subscribeSeconds,
    required String watermarkPosition,
    required String channelName,
    required String outputDir,
    String? watermarkAssetPath,
    Map<String, dynamic>? dubConfig,
    Map<String, dynamic>? translateConfig,
  }) async {
    try {
      final Map<String, dynamic> arguments = {
        'inputPath': inputPath,
        'mode': mode.value,
        'segmentSeconds': segmentSeconds,
        'subscribeSeconds': subscribeSeconds,
        'watermarkPosition': watermarkPosition,
        'channelName': channelName,
        'outputDir': outputDir,
        if (watermarkAssetPath != null) 'watermarkAssetPath': watermarkAssetPath,
        if (dubConfig != null) 'dubConfig': dubConfig,
        if (translateConfig != null) 'translateConfig': translateConfig,
      };

      final dynamic result = await _channel.invokeMethod('splitAndExport', arguments);
      
      if (result is List) {
        return result.cast<String>();
      }
      
      return [];
    } on PlatformException catch (e) {
      throw Exception('Failed to split video: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  /// Get video duration in seconds
  Future<double> getVideoDuration(String videoPath) async {
    try {
      final double? duration = await _channel.invokeMethod('getVideoDuration', {'path': videoPath});
      return duration ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// Cancel ongoing export
  Future<void> cancelExport() async {
    try {
      await _channel.invokeMethod('cancelExport');
    } catch (e) {
      // Ignore cancellation errors
    }
  }

  /// Compute segment ranges for a given duration
  static List<({double start, double end})> computeSegments(
    double durationSeconds,
    int segmentSeconds,
  ) {
    if (durationSeconds <= 0 || segmentSeconds <= 0) {
      return [];
    }

    final count = (durationSeconds / segmentSeconds).ceil();
    return List.generate(count, (i) {
      final start = i * segmentSeconds.toDouble();
      final end = (start + segmentSeconds).clamp(0.0, durationSeconds);
      return (start: start, end: end);
    });
  }
}
