import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'local_backend_api.dart';
import 'local_whisper_service.dart';

class TranscriptItem {
  final double startSec;
  final double endSec;
  final String text;

  TranscriptItem({
    required this.startSec,
    required this.endSec,
    required this.text,
  });
}

class BestScene {
  final double startSec;
  final double endSec;
  final int score;

  BestScene({
    required this.startSec,
    required this.endSec,
    required this.score,
  });
}

class AiBestScenesOptions {
  final int srtChunkSize;
  final double minSceneSec;
  final double maxSceneSec;
  final int scoreThreshold;
  final double minGapSec;
  final int maxScenes;
  final double maxTotalSec;
  final int segmentsPerChunk;

  const AiBestScenesOptions({
    this.srtChunkSize = 0,
    this.minSceneSec = 0,
    this.maxSceneSec = 0,
    this.scoreThreshold = 72,
    this.minGapSec = 2.0,
    this.maxScenes = 0,
    this.maxTotalSec = 0,
    this.segmentsPerChunk = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'srt_chunk_size': srtChunkSize,
      'min_scene_sec': minSceneSec,
      'max_scene_sec': maxSceneSec,
      'score_threshold': scoreThreshold,
      'min_gap_sec': minGapSec,
      'max_scenes': maxScenes,
      'max_total_sec': maxTotalSec,
      'segments_per_chunk': segmentsPerChunk,
    };
  }
}

class AiBestScenesService {
  final LocalBackendAPI _api = LocalBackendAPI();
  final LocalWhisperService _localWhisper = LocalWhisperService();

  void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    print('[AiBestScenesService][$ts] $message');
  }

  Future<String> extractAudio16kMono({
    required String inputVideoPath,
    required String projectId,
    void Function(String step)? onStep,
  }) async {
    onStep?.call('Extract audio');
    _log('Extract audio start | video=$inputVideoPath');
    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/projects/$projectId/ai_audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final wavPath = '${audioDir.path}/input_audio_16k.wav';
    final cmd = '-y -i "$inputVideoPath" '
        '-vn -ac 1 -ar 16000 -c:a pcm_s16le "$wavPath"';

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Failed to extract audio track from selected video');
    }

    _log('Extract audio done | wav=$wavPath');
    return wavPath;
  }

  Future<List<TranscriptItem>> loadTranscriptSrtForVideo({
    required String videoPath,
    required String projectId,
    void Function(String step)? onStep,
  }) async {
    final sidecarBase = videoPath.replaceAll(RegExp(r'\.[^./]+$'), '');
    final sidecarSrt = File('$sidecarBase.srt');

    if (await sidecarSrt.exists()) {
      _log('Using sidecar SRT: ${sidecarSrt.path}');
      final raw = await sidecarSrt.readAsString();
      return _parseSrt(raw);
    }

    _log('No sidecar SRT found | extracting audio then transcribing...');
    final wavPath = await extractAudio16kMono(
      inputVideoPath: videoPath,
      projectId: projectId,
      onStep: onStep,
    );
    final wavSrt = File(wavPath.replaceAll(RegExp(r'\.wav$'), '.srt'));
    if (!await wavSrt.exists()) {
      try {
        onStep?.call('Convert audio to text');
        _log('Running local whisper transcription on phone...');
        final srtText = await _localWhisper
            .transcribeAudioToSrt(
              audioPath: wavPath,
              onProgress: (p) {
                final stage = (p['stage']?.toString() ?? '').toLowerCase();
                final processed = (p['processedChunks'] as num?)?.toInt();
                final total = (p['totalChunks'] as num?)?.toInt();
                final message = p['message']?.toString();
                if (message != null && message.trim().isNotEmpty) {
                  onStep?.call(message.trim());
                  return;
                }
                if (stage == 'transcribing' &&
                    processed != null &&
                    total != null) {
                  onStep?.call(
                      'Convert audio to text chunk $processed/$total (remaining ${total - processed})');
                } else if (stage == 'loading_model') {
                  onStep?.call('Convert audio to text | loading model');
                } else if (stage == 'done') {
                  onStep?.call('Convert audio to text done');
                }
              },
            )
            .timeout(const Duration(minutes: 15));
        await wavSrt.writeAsString(srtText);
        _log('Local whisper SRT saved: ${wavSrt.path}');
      } catch (localError) {
        onStep?.call('Convert audio to text');
        _log('Local whisper failed, fallback to backend whisper: $localError');
        final srtText = await _api
            .transcribeAudioToSrt(audioPath: wavPath)
            .timeout(const Duration(minutes: 10));
        await wavSrt.writeAsString(srtText);
        _log('Backend whisper SRT saved: ${wavSrt.path}');
      }
    }

    final raw = await wavSrt.readAsString();
    return _parseSrt(raw);
  }

  List<TranscriptItem> _parseSrt(String raw) {
    final blocks = raw.split(RegExp(r'\n\s*\n'));
    final out = <TranscriptItem>[];

    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (lines.length < 2) continue;
      final timingLine = lines.firstWhere(
        (l) => l.contains('-->'),
        orElse: () => '',
      );
      if (timingLine.isEmpty) continue;
      final parts = timingLine.split('-->');
      if (parts.length != 2) continue;

      final startSec = _srtTsToSec(parts[0].trim());
      final endSec = _srtTsToSec(parts[1].trim());
      if (endSec <= startSec) continue;

      final textLines = lines
          .where((l) => !l.contains('-->') && !RegExp(r'^\d+$').hasMatch(l))
          .map(_stripSrtTags)
          .toList();
      final text = textLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;

      out.add(TranscriptItem(startSec: startSec, endSec: endSec, text: text));
    }
    return out;
  }

  String _stripSrtTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  double _srtTsToSec(String ts) {
    final m = RegExp(r'(\d+):(\d+):(\d+)[,.](\d+)').firstMatch(ts);
    if (m == null) return 0;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final s = int.parse(m.group(3)!);
    final ms = int.parse(m.group(4)!.padRight(3, '0').substring(0, 3));
    return h * 3600 + min * 60 + s + ms / 1000.0;
  }

  List<List<TranscriptItem>> chunkByItemCount(
    List<TranscriptItem> items, {
    int chunkSize = 220,
  }) {
    final chunks = <List<TranscriptItem>>[];
    if (items.isEmpty) return chunks;

    final safeChunkSize = max(1, chunkSize);
    for (int i = 0; i < items.length; i += safeChunkSize) {
      final end = min(i + safeChunkSize, items.length);
      chunks.add(items.sublist(i, end));
    }

    return chunks;
  }

  List<TranscriptItem> _tailItems(List<TranscriptItem> items, int count) {
    if (items.isEmpty || count <= 0) return const [];
    if (items.length <= count) return items;
    return items.sublist(items.length - count);
  }

  Future<List<BestScene>> askLlmAcrossChunks({
    required String projectId,
    required List<List<TranscriptItem>> chunks,
    required AiBestScenesOptions options,
    void Function({
      required int chunkIndex,
      required int totalChunks,
      required int processedChunks,
      required int remainingChunks,
      required bool fromCache,
    })? onChunkProgress,
  }) async {
    _log('Bedrock chunk analysis start | chunks=${chunks.length}');
    final all = <BestScene>[];
    final cacheRows = await _api.getAiChunkCache(projectId: projectId);
    final cache = <int, List<dynamic>>{};
    for (final row in cacheRows) {
      final idx = (row['chunkIndex'] as num?)?.toInt();
      final segments = row['segments'] as List<dynamic>? ?? const [];
      if (idx != null) cache[idx] = segments;
    }

    const overlapItems = 3;
    for (int i = 0; i < chunks.length; i++) {
      final items = chunks[i]
          .map((e) =>
              {'startSec': e.startSec, 'endSec': e.endSec, 'text': e.text})
          .toList();
      final chunkIndex = i + 1;
      final contextText = i == 0
          ? ''
          : _tailItems(chunks[i - 1], overlapItems)
              .map((e) =>
                  '[${e.startSec.toStringAsFixed(1)}-${e.endSec.toStringAsFixed(1)}] ${e.text}')
              .join('\n');

      List<dynamic> segs = cache[chunkIndex] ?? const [];
      if (segs.isEmpty) {
        final res = await _api.analyzeAiBestScenesChunk(
          chunkIndex: chunkIndex,
          items: items,
          contextText: contextText,
          minSceneSec: options.minSceneSec,
          maxSceneSec: options.maxSceneSec,
          segmentsPerChunk: options.segmentsPerChunk,
        );
        _log('Chunk analyzed ${i + 1}/${chunks.length}');
        segs = (res['segments'] as List<dynamic>? ?? const []);
        await _api.saveAiChunkCache(
          projectId: projectId,
          chunkIndex: chunkIndex,
          chunkInput: items,
          contextText: contextText,
          segments:
              segs.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
        onChunkProgress?.call(
          chunkIndex: chunkIndex,
          totalChunks: chunks.length,
          processedChunks: i + 1,
          remainingChunks: chunks.length - (i + 1),
          fromCache: false,
        );
      } else {
        _log('Chunk cache hit ${i + 1}/${chunks.length}');
        onChunkProgress?.call(
          chunkIndex: chunkIndex,
          totalChunks: chunks.length,
          processedChunks: i + 1,
          remainingChunks: chunks.length - (i + 1),
          fromCache: true,
        );
      }
      for (final s in segs) {
        all.add(BestScene(
          startSec: (s['startSec'] as num?)?.toDouble() ?? 0,
          endSec: (s['endSec'] as num?)?.toDouble() ?? 0,
          score: (s['score'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    _log('Bedrock chunk analysis complete | rawScenes=${all.length}');
    return _selectNonOverlapping(all, options);
  }

  List<BestScene> _selectNonOverlapping(
    List<BestScene> scenes,
    AiBestScenesOptions options,
  ) {
    final sorted = [...scenes]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.startSec.compareTo(b.startSec);
      });

    final chosen = <BestScene>[];
    double totalDuration = 0;

    for (final s in sorted) {
      final dur = s.endSec - s.startSec;
      if (dur <= 0.5) continue;
      if (s.score < options.scoreThreshold) continue;

      final hasGapConflict = chosen.any((c) =>
          !(s.endSec + options.minGapSec <= c.startSec ||
              s.startSec >= c.endSec + options.minGapSec));
      if (hasGapConflict) continue;

      if (chosen.length >= options.maxScenes) break;
      if (totalDuration + dur > options.maxTotalSec) break;

      chosen.add(s);
      totalDuration += dur;
    }

    chosen.sort((a, b) => a.startSec.compareTo(b.startSec));
    return chosen;
  }

  Future<List<String>> cutScenesLocally({
    required String inputPath,
    required List<BestScene> scenes,
    required String projectId,
    void Function({
      required int clipIndex,
      required int totalClips,
      required int processedClips,
      required int remainingClips,
    })? onClipProgress,
  }) async {
    _log('Local scene cutting start | scenes=${scenes.length}');
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${appDir.path}/projects/$projectId/ai_clips');
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final outputs = <String>[];
    for (int i = 0; i < scenes.length; i++) {
      final s = scenes[i];
      final outPath =
          '${outDir.path}/scene_${(i + 1).toString().padLeft(3, '0')}.mp4';
      final dur = (s.endSec - s.startSec).toStringAsFixed(3);
      final start = s.startSec.toStringAsFixed(3);

      final cmd = '-y -ss $start -t $dur -i "$inputPath" '
          '-vf "setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,format=yuv420p" '
          '-af "asetpts=PTS-STARTPTS" '
          '-c:v libx264 -preset veryfast -crf 20 -c:a aac -b:a 192k '
          '-movflags +faststart "$outPath"';

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('Failed to cut scene ${i + 1}');
      }
      outputs.add(outPath);
      _log('Cut scene ${i + 1}/${scenes.length} -> $outPath');
      onClipProgress?.call(
        clipIndex: i + 1,
        totalClips: scenes.length,
        processedClips: i + 1,
        remainingClips: scenes.length - (i + 1),
      );
    }
    _log('Local scene cutting complete');
    return outputs;
  }

  Future<String> mergeScenes({
    required List<String> clipPaths,
    required String projectId,
  }) async {
    if (clipPaths.isEmpty) throw Exception('No clips to merge');
    _log('Merge start | clips=${clipPaths.length}');
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${appDir.path}/projects/$projectId/ai_result');
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final listFile = File('${outDir.path}/concat_list.txt');
    final lines =
        clipPaths.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n');
    await listFile.writeAsString(lines);

    final finalOut = '${outDir.path}/best_scenes_final.mp4';
    final cmd = '-y -f concat -safe 0 -i "${listFile.path}" '
        '-c:v libx264 -preset veryfast -crf 20 -c:a aac -b:a 192k '
        '-movflags +faststart "$finalOut"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Failed to merge scene clips');
    }
    _log('Merge complete | output=$finalOut');
    return finalOut;
  }
}
