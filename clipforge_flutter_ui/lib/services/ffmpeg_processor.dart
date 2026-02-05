import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';

/// Result of FFmpeg processing
class ProcessResult {
  final bool isSuccess;
  final String? error;
  final String? outputPath;

  ProcessResult({
    required this.isSuccess,
    this.error,
    this.outputPath,
  });
}

class FFmpegProcessor {
  static const int _canvasWidth = 1080;
  static const int _canvasHeight = 1920;
  static const int _watermarkWidth = 180;
  static const double _watermarkAlpha = 0.55;

  // Safe area margins for text placement
  static const int _marginX = 60;
  static const int _marginY = 200;
  static const int _maxTextX = 860;
  static const int _maxTextY = 1400;

  /// Process a single video chunk with watermark and channel name
  Future<ProcessResult> processChunk({
    required String inputPath,
    required String outputPath,
    required double startSec,
    required double durationSec,
    String? watermarkPath,
    required String channelName,
    String flipMode = 'none',
    bool randomTextPosition = true,
    String watermarkPosition = 'bottom_right',
    double watermarkAlpha = _watermarkAlpha,
    Function(double)? onProgress,
  }) async {
    try {
      final (txtX, txtY) = randomTextPosition
          ? _generateRandomTextPosition()
          : (_canvasWidth ~/ 2, _canvasHeight - 300);

      final (wmX, wmY) = _getWatermarkPosition(watermarkPosition);

      final command = _buildFFmpegCommand(
        inputPath: inputPath,
        outputPath: outputPath,
        startSec: startSec,
        durationSec: durationSec,
        watermarkPath: watermarkPath,
        channelName: channelName,
        flipMode: flipMode,
        txtX: txtX,
        txtY: txtY,
        wmX: wmX,
        wmY: wmY,
        wmAlpha: watermarkAlpha,
      );

      print('[FFmpegProcessor] Command: $command');

      double currentProgress = 0.0;

      // Run async
      final FFmpegSession session = await FFmpegKit.executeAsync(
        command,
        (s) async {
          final rc = await s.getReturnCode();
          print('[FFmpegProcessor] ✅ completion callback rc=${rc?.getValue()}');
        },
        (log) {
          final msg = log.getMessage();
          if (msg.trim().isNotEmpty) {
            print('[FFmpegProcessor] $msg');
          }
        },
        (Statistics stats) {
          if (onProgress == null) return;
          final timeMs = stats.getTime();
          if (timeMs > 0) {
            final progress = timeMs / (durationSec * 1000.0);
            if (progress > currentProgress && progress <= 1.0) {
              currentProgress = progress;
              onProgress(progress);
            }
          }
        },
      );

      // ✅ IMPORTANT: wait until session is actually completed
      await _waitForSessionToFinish(session);

      final returnCode = await session.getReturnCode();
      final rcVal = returnCode?.getValue();

      // Fetch output/fail info for diagnostics
      final failStackTrace = await session.getFailStackTrace();
      final output = await session.getOutput();

      // ✅ Success path
      if (ReturnCode.isSuccess(returnCode)) {
        // Validate output exists and has size (prevents false positives)
        final ok = await _verifyOutputFile(outputPath);
        if (!ok) {
          return ProcessResult(
            isSuccess: false,
            error:
                'FFmpeg returned success but output file missing/too small.\n'
                'rc=$rcVal\n${output ?? ''}',
          );
        }

        print('[FFmpegProcessor] ✅ Success: $outputPath');
        return ProcessResult(isSuccess: true, outputPath: outputPath);
      }

      // ❌ Fail path (capture real errors)
      final errorMsg =
          (failStackTrace != null && failStackTrace.trim().isNotEmpty)
              ? failStackTrace
              : (output != null && output.trim().isNotEmpty)
                  ? output
                  : 'FFmpeg failed (rc=$rcVal) with no output';

      print('[FFmpegProcessor] ❌ Failed: $errorMsg');

      return ProcessResult(isSuccess: false, error: errorMsg);
    } catch (e, st) {
      print('[FFmpegProcessor] Exception: $e\n$st');
      return ProcessResult(isSuccess: false, error: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers: wait + verification
  // ---------------------------------------------------------------------------

  Future<void> _waitForSessionToFinish(FFmpegSession session) async {
    // FFmpegKit "state" becomes COMPLETED when done.
    // Some versions return enum-like values; we keep it robust via string.
    while (true) {
      final state = await session.getState();
      final s = state.toString().toUpperCase();
      if (s.contains('COMPLETED') || s.contains('FAILED')) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<bool> _verifyOutputFile(String outputPath) async {
    try {
      final f = File(outputPath);
      if (!await f.exists()) return false;
      final len = await f.length();
      return len > 50 * 1024; // > 50KB
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Command building
  // ---------------------------------------------------------------------------

  String _escapeDrawtext(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(':', '\\:');
  }

  String _buildFFmpegCommand({
    required String inputPath,
    required String outputPath,
    required double startSec,
    required double durationSec,
    String? watermarkPath,
    required String channelName,
    required String flipMode,
    required int txtX,
    required int txtY,
    required int wmX,
    required int wmY,
    required double wmAlpha,
  }) {
    final flip = flipMode != 'none' ? '$flipMode,' : '';
    final text = _escapeDrawtext(channelName);

    const fontFile = '/system/fonts/Roboto-Regular.ttf';

    // No watermark => use -vf (more stable)
    if (watermarkPath == null || watermarkPath.isEmpty) {
      final vf = [
        '${flip}scale=$_canvasWidth:$_canvasHeight:force_original_aspect_ratio=decrease',
        'pad=$_canvasWidth:$_canvasHeight:(ow-iw)/2:(oh-ih)/2',
        'format=yuv420p',
        "drawtext=fontfile=$fontFile:text='$text':x=$txtX:y=$txtY:fontsize=36:fontcolor=white:borderw=3:bordercolor=black@0.6",
      ].join(',');

      return [
        '-y',
        '-hide_banner',
        '-loglevel',
        'info',
        '-ss',
        startSec.toStringAsFixed(3),
        '-t',
        durationSec.toStringAsFixed(3),
        '-i',
        inputPath,
        '-vf',
        vf,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
        outputPath,
      ].join(' ');
    }

    // With watermark => filter_complex
    final graph = [
      "[0:v]${flip}"
          "scale=$_canvasWidth:$_canvasHeight:force_original_aspect_ratio=decrease,"
          "pad=$_canvasWidth:$_canvasHeight:(ow-iw)/2:(oh-ih)/2,"
          "setsar=1,"
          "format=rgba[v0]",

      "[1:v]"
          "scale=$_watermarkWidth:-2,"
          "format=rgba,"
          "colorchannelmixer=aa=$wmAlpha[wm]",

      // shortest=1 prevents infinite output when watermark input is looped
      "[v0][wm]overlay=$wmX:$wmY:shortest=1[v1]",

      "[v1]drawtext="
          "fontfile=$fontFile:"
          "text='$text':"
          "x=$txtX:y=$txtY:"
          "fontsize=36:fontcolor=white:"
          "borderw=3:bordercolor=black@0.6"
          "[v2]",

      "[v2]format=yuv420p[v]"
    ].join(';');

    return [
      '-y',
      '-hide_banner',
      '-loglevel',
      'info',
      '-ss',
      startSec.toStringAsFixed(3),
      '-t',
      durationSec.toStringAsFixed(3),
      '-i',
      inputPath,
      '-loop',
      '1',
      '-i',
      watermarkPath,
      '-filter_complex',
      '"$graph"',
      '-map',
      '[v]',
      '-map',
      '0:a:0?',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-shortest',
      '-movflags',
      '+faststart',
      outputPath,
    ].join(' ');
  }

  // ---------------------------------------------------------------------------
  // Position helpers
  // ---------------------------------------------------------------------------

  (int, int) _generateRandomTextPosition() {
    final random = Random();
    final x = _marginX + random.nextInt(_maxTextX - _marginX);
    final y = _marginY + random.nextInt(_maxTextY - _marginY);
    return (x, y);
  }

  (int, int) _getWatermarkPosition(String position) {
    const margin = 40;

    switch (position) {
      case 'top_left':
        return (margin, margin);
      case 'top_right':
        return (_canvasWidth - _watermarkWidth - margin, margin);
      case 'bottom_left':
        return (margin, _canvasHeight - 100 - margin);
      case 'bottom_right':
      default:
        return (
          _canvasWidth - _watermarkWidth - margin,
          _canvasHeight - 100 - margin
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Probe helpers
  // ---------------------------------------------------------------------------

  static Future<double?> getVideoDuration(String videoPath) async {
    try {
      // Use ffprobe to avoid decoding the whole video stream.
      final session = await FFprobeKit.execute(
          '-v error -show_entries format=duration -of default=nk=1:nw=1 "$videoPath"');
      final output = await session.getOutput();
      if (output != null) {
        final firstLine = output
            .split('\n')
            .map((e) => e.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        final parsed = double.tryParse(firstLine);
        if (parsed != null && parsed > 0) return parsed;
      }

      // Fallback path for devices/builds where ffprobe output can be empty.
      final fallback = await FFmpegKit.execute('-i "$videoPath" -f null -');
      final ffmpegOutput = await fallback.getOutput();
      if (ffmpegOutput == null) return null;
      final durationRegex = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})');
      final match = durationRegex.firstMatch(ffmpegOutput);
      if (match == null) return null;
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = double.parse(match.group(3)!);
      return hours * 3600 + minutes * 60 + seconds;
    } catch (e) {
      print('[FFmpegProcessor] Error getting duration: $e');
      return null;
    }
  }

  static Future<String?> getVideoResolution(String videoPath) async {
    try {
      // Probe only first video stream resolution.
      final session = await FFprobeKit.execute(
          '-v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$videoPath"');
      final output = await session.getOutput();
      if (output != null) {
        final firstLine = output
            .split('\n')
            .map((e) => e.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        final resolutionRegex = RegExp(r'^(\d{2,5})x(\d{2,5})$');
        final match = resolutionRegex.firstMatch(firstLine);
        if (match != null) return '${match.group(1)}x${match.group(2)}';
      }

      // Fallback path for devices/builds where ffprobe output can be empty.
      final fallback = await FFmpegKit.execute('-i "$videoPath" -f null -');
      final ffmpegOutput = await fallback.getOutput();
      if (ffmpegOutput == null) return null;
      final resolutionRegex = RegExp(r'(\d{3,5})x(\d{3,5})');
      final match = resolutionRegex.firstMatch(ffmpegOutput);
      if (match == null) return null;
      return '${match.group(1)}x${match.group(2)}';
    } catch (e) {
      print('[FFmpegProcessor] Error getting resolution: $e');
      return null;
    }
  }
}
