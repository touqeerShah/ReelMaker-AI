import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';

import '../services/local_backend_api.dart';
import '../models/video_project.dart';
import '../models/processing_job.dart';
import '../services/local_queue_db.dart';
import '../services/video_queue_worker.dart';
import '../services/ffmpeg_processor.dart';
import '../services/permission_service.dart';
import '../services/ai_best_scenes_service.dart';
import '../services/gallery_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../widgets/permission_request_dialog.dart';
import '../models/models.dart';
import 'project_detail_screen.dart';

class CreateShortsWizard extends StatefulWidget {
  const CreateShortsWizard({super.key, this.initialCategory});

  final String? initialCategory; // 'split' or 'summary'

  @override
  State<CreateShortsWizard> createState() => _CreateShortsWizardState();
}

class _CreateShortsWizardState extends State<CreateShortsWizard> {
  final PageController _controller = PageController();
  int _step = 0;
  final ValueNotifier<double> _uploadProgress = ValueNotifier(0.0);
  final ValueNotifier<String> _uploadStatus =
      ValueNotifier('Preparing upload...');

  // Step 1: Video Selection
  // String? _selectedVideoPath;
  PlatformFile? _selectedVideoFile;
  String? _selectedVideoPath; // non-web
  Uint8List? _selectedVideoBytes; // web

  // Step 2: Category & Processing Mode
  String _category = 'split'; // 'split' or 'summary'
  String _processingMode = 'split_only';
  // Modes: split_only, split_voice, split_translate, ai_best_scenes, ai_best_scenes_split, ai_summary_hybrid, ai_story_only

  // Split settings (always shown)
  int _segmentSeconds = 60;
  int _subscribeSeconds = 5;
  String _watermarkPosition = 'Top-right';
  // Channel name moved to Settings page

  // Voice settings (for split_voice mode)
  String _voiceStyle = 'Natural';
  double _voiceSpeed = 1.0;

  // Translation settings (for split_translate mode)
  String _targetLanguage = 'Spanish';

  // AI mode settings (for all AI summarization modes)
  String _aiLanguage = 'English';
  String _aiVoice = 'af_heart';
  bool _keepOriginalAudio = false;
  bool _showAiAdvancedTuning = false;
  bool _aiAddSubtitles = false;
  bool _aiAutoChunk = true;
  bool _aiAnySceneLength = true;

  // AI Best Scenes tuning (important knobs only)
  int _aiSrtChunkSize = 220;
  double _aiMinSceneSec = 20;
  double _aiMaxSceneSec = 55;
  int _aiScoreThreshold = 72;
  double _aiMinGapSec = 2.0;
  int _aiSegmentsPerChunk = 1;

  // AI Summary tuning (hybrid/story)
  bool _showAiSummaryTuning = false;
  double _ttsDuckVolume = 0.18;
  double _ttsMaxSpeedup = 1.35;
  double _ttsMinSlowdown = 0.85;
  double _ttsFadeSec = 0.12;
  int _aiContextOverlap = 6;
  int _summarySegmentsPerChunk = 3;
  int _summaryMaxSegments = 0;
  bool _summaryPlanOnly = true;
  final AudioPlayer _voicePlayer = AudioPlayer();
  String? _lastVoicePreview;

  // Channel name for watermark
  String? _selectedChannelName = 'My Channel';

  // Step 4: Export/Share
  bool _exportLocal = true;
  final Map<String, bool> _socialMediaTargets = {
    'youtube': false,
    'instagram': false,
    'tiktok': false,
    'facebook': false,
  };
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isAiBestScenesMode =>
      _processingMode == 'ai_best_scenes' ||
      _processingMode == 'ai_best_scenes_split';

  bool get _isAiBackendMode => _processingMode.startsWith('ai_');

  bool get _isAiSummaryMode =>
      _processingMode == 'ai_summary_hybrid' ||
      _processingMode == 'ai_story_only';

  static const List<Map<String, String>> _voiceOptions = [
    {'id': 'af_heart', 'name': 'Heart', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_alloy', 'name': 'Alloy', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_aoede', 'name': 'Aoede', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_bella', 'name': 'Bella', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_jessica', 'name': 'Jessica', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_kore', 'name': 'Kore', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_nicole', 'name': 'Nicole', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_nova', 'name': 'Nova', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_river', 'name': 'River', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_sarah', 'name': 'Sarah', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'af_sky', 'name': 'Sky', 'language': 'en-us', 'gender': 'Female'},
    {'id': 'am_adam', 'name': 'Adam', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_echo', 'name': 'Echo', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_eric', 'name': 'Eric', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_fenrir', 'name': 'Fenrir', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_liam', 'name': 'Liam', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_michael', 'name': 'Michael', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_onyx', 'name': 'Onyx', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_puck', 'name': 'Puck', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'am_santa', 'name': 'Santa', 'language': 'en-us', 'gender': 'Male'},
    {'id': 'bf_emma', 'name': 'Emma', 'language': 'en-gb', 'gender': 'Female'},
    {'id': 'bf_isabella', 'name': 'Isabella', 'language': 'en-gb', 'gender': 'Female'},
    {'id': 'bm_george', 'name': 'George', 'language': 'en-gb', 'gender': 'Male'},
    {'id': 'bm_lewis', 'name': 'Lewis', 'language': 'en-gb', 'gender': 'Male'},
    {'id': 'bf_alice', 'name': 'Alice', 'language': 'en-gb', 'gender': 'Female'},
    {'id': 'bf_lily', 'name': 'Lily', 'language': 'en-gb', 'gender': 'Female'},
    {'id': 'bm_daniel', 'name': 'Daniel', 'language': 'en-gb', 'gender': 'Male'},
    {'id': 'bm_fable', 'name': 'Fable', 'language': 'en-gb', 'gender': 'Male'},
  ];

  String _voiceLabel(String id) {
    final match = _voiceOptions
        .cast<Map<String, String>>()
        .firstWhere((v) => v['id'] == id, orElse: () => {});
    if (match.isEmpty) return id;
    final name = match['name'] ?? id;
    final lang = match['language']?.toUpperCase() ?? '';
    final gender = match['gender'] ?? '';
    return [name, lang, gender].where((e) => e.isNotEmpty).join(' • ');
  }

  Future<void> _playVoicePreview(String voiceId) async {
    final base =
        LocalBackendAPI().baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/voices/voice_$voiceId.wav';
    try {
      _lastVoicePreview = voiceId;
      await _voicePlayer.setUrl(url);
      await _voicePlayer.play();
    } catch (e) {
      debugPrint('Voice preview failed: $e');
    }
  }

  void _logStep(String message) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[CreateShortsWizard][$ts] $message');
  }

  Future<T> _runStep<T>(
    String name,
    Future<T> Function() action, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _logStep('START: $name');
    try {
      final result = await action().timeout(timeout);
      _logStep('DONE: $name');
      return result;
    } on TimeoutException {
      _logStep('TIMEOUT: $name');
      throw Exception(
          '$name timed out. Please check backend connection and retry.');
    }
  }

  @override
  void initState() {
    super.initState();
    // Set initial category if provided from home page
    if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
      // Set default mode for category
      if (_category == 'summary') {
        _processingMode = 'ai_best_scenes';
      } else {
        _processingMode = 'split_only';
      }
    }
  }

  static const _steps = <String>[
    'Select video',
    'Processing & Settings',
    'Review',
    'Export/Share',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _uploadProgress.dispose();
    _uploadStatus.dispose();
    _voicePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CfAppBar(
        title: const Text('Create Shorts'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                  bottom: BorderSide(color: cs.outline.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                for (int i = 0; i < _steps.length; i++) ...[
                  if (i > 0)
                    Expanded(
                        child: Container(
                            height: 2,
                            color: i <= _step
                                ? cs.primary
                                : cs.outline.withOpacity(0.3))),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: i <= _step ? cs.primary : cs.surface,
                      border: Border.all(
                          color: i <= _step
                              ? cs.primary
                              : cs.outline.withOpacity(0.3),
                          width: 2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: i < _step
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  color: i == _step
                                      ? Colors.white
                                      : cs.onSurface.withOpacity(0.5),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepSelectVideo(context),
                _stepProcessingAndSettings(context),
                _stepReview(context),
                _stepExportShare(context),
              ],
            ),
          ),
          _bottomBar(context),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final isLast = _step == _steps.length - 1;
    final canProceed = _canProceed();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.96),
          border: Border(
              top: BorderSide(
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.12))),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _step == 0 ? null : _back,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CfButton(
                onPressed: canProceed ? (isLast ? _finish : _next) : null,
                child: Text(isLast ? 'Start Processing' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _selectedVideoFile != null;
      case 1:
        return true; // No validation needed for settings
      case 2:
        return true; // Review always allows proceed
      case 3:
        return _exportLocal || _socialMediaTargets.values.any((v) => v);
      default:
        return false;
    }
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      _controller.animateToPage(_step,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _controller.animateToPage(_step,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _finish() async {
    _logStep(
        'Start pressed | mode=$_processingMode | category=$_category | file=${_selectedVideoFile?.name} | path=$_selectedVideoPath');
    // Check if on web - FFmpeg doesn't work on web
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Video processing is not supported on web. Please use Android, iOS, or desktop app.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    try {
      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Processing'),
          content: ValueListenableBuilder<double>(
            valueListenable: _uploadProgress,
            builder: (context, progress, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: _uploadStatus,
                    builder: (context, status, __) => Text(
                      status,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                      value: progress > 0 ? progress : null),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%'),
                ],
              );
            },
          ),
        ),
      );

      // 1. Upload video to local backend server
      final api = LocalBackendAPI();
      if (!api.isAuthenticated) {
        throw Exception('Not authenticated - please login first');
      }
      _logStep('API initialized | baseUrl=${api.baseUrl}');
      final isAiBackendMode = _isAiBackendMode;

      double? videoDuration;
      String? videoResolution;

      // 2. Get video metadata only when needed (AI best-scenes can start immediately).
      if (isAiBackendMode) {
        videoDuration = 0;
        videoResolution = null;
        _logStep('AI mode: skipping upfront metadata probe');
      } else {
        _logStep('Reading video duration/resolution (parallel)...');
        final videoMeta = await _runStep(
          'Read video metadata',
          () async {
            final results = await Future.wait([
              FFmpegProcessor.getVideoDuration(
                  kIsWeb ? '' : _selectedVideoPath!),
              FFmpegProcessor.getVideoResolution(
                  kIsWeb ? '' : _selectedVideoPath!),
            ]);
            return (results[0] as double?, results[1] as String?);
          },
          timeout: const Duration(seconds: 120),
        );
        videoDuration = videoMeta.$1;
        videoResolution = videoMeta.$2;
        _logStep(
            'Video metadata read | duration=$videoDuration | resolution=$videoResolution');
        if (videoDuration == null) {
          throw Exception('Could not determine video duration');
        }
      }

      // 3. Store video metadata (split mode) or upload full video (AI backend)
      Map<String, dynamic> videoMetadata;
      if (isAiBackendMode) {
        if (_selectedVideoPath == null) {
          throw Exception('Video file path is missing');
        }
        _logStep('Uploading video to backend for AI processing...');
        _uploadStatus.value = 'Uploading video to backend...';
        _uploadProgress.value = 0.01;
        videoMetadata = await _runStep(
          'Upload video',
          () => api.uploadVideoChunked(
            videoFile: File(_selectedVideoPath!),
            title: _selectedVideoFile!.name,
            durationSec: videoDuration ?? 0,
            resolution: videoResolution,
            parallelUploads: 3,
            onChunk: (partIndex, totalParts) {
              _uploadStatus.value =
                  'Uploading chunk $partIndex/$totalParts (3 parallel)...';
            },
            onProgress: (progress, sent, total) {
              _uploadStatus.value =
                  'Uploading... ${(progress * 100).toStringAsFixed(0)}%';
              _uploadProgress.value = progress;
            },
          ),
          timeout: const Duration(minutes: 30),
        );
        _uploadStatus.value = 'Upload complete. Preparing job...';
        _uploadProgress.value = 1.0;
      } else {
        videoMetadata = await _runStep(
          'Create video metadata',
          () => api.createVideoMetadata(
            title: _selectedVideoFile!.name,
            durationSec: videoDuration ?? 0,
            resolution: videoResolution,
            localPath: _selectedVideoPath!,
            segmentDuration: _segmentSeconds,
            overlayDuration: 3.0, // Subscribe overlay duration
            logoPosition: 'bottom_right', // From settings
            watermarkEnabled: true,
            watermarkAlpha: 0.55,
          ),
        );
      }

      final videoMap =
          (videoMetadata['video'] as Map?)?.cast<String, dynamic>() ??
              videoMetadata;
      final videoId = videoMap['id'];
      _logStep(
          'Video ready | videoId=$videoId | ai=$isAiBackendMode | uploaded=${isAiBackendMode}');

      final safeVideoDuration = videoDuration ?? 0;

      // 4. Calculate chunks
      final totalChunks =
          isAiBackendMode ? 1 : (safeVideoDuration / _segmentSeconds).ceil();
      _logStep('Total chunks calculated: $totalChunks');

      // 5. Create project settings
      final settings = ProjectSettings(
        category: _category,
        segmentSeconds: _segmentSeconds,
        watermarkEnabled: true,
        watermarkPosition: 'bottom_right',
        watermarkAlpha: 0.55,
        subtitlesEnabled: _isAiBackendMode ? _aiAddSubtitles : false,
        channelName: _selectedChannelName ?? 'My Channel',
        textRandomPosition: true,
        flipMode: 'none',
        outputResolution: '1080x1920',
        processingMode: _processingMode,
      );

      final aiOptions = AiBestScenesOptions(
        srtChunkSize: _aiAutoChunk ? 0 : _aiSrtChunkSize,
        minSceneSec: _aiAnySceneLength ? 0 : _aiMinSceneSec,
        maxSceneSec: _aiAnySceneLength ? 0 : _aiMaxSceneSec,
        scoreThreshold: _aiScoreThreshold,
        minGapSec: _aiMinGapSec,
        maxScenes: 0,
        maxTotalSec: 0,
        segmentsPerChunk: _aiSegmentsPerChunk,
        summaryMinSegSec: 0,
        summaryMaxSegSec: 0,
        summarySegmentsPerChunk:
            _isAiSummaryMode ? _summarySegmentsPerChunk : 0,
        summaryMaxSegments: _isAiSummaryMode ? _summaryMaxSegments : 0,
        summaryPlanOnly: _isAiSummaryMode ? _summaryPlanOnly : false,
        maxSpeedup: _isAiSummaryMode ? _ttsMaxSpeedup : 0,
        minSlowdown: _isAiSummaryMode ? _ttsMinSlowdown : 0,
        duckVolume: _processingMode == 'ai_summary_hybrid' ? _ttsDuckVolume : 0,
        ttsFadeSec: _isAiSummaryMode ? _ttsFadeSec : 0,
        ttsVoice: _isAiSummaryMode ? _aiVoice : '',
        contextOverlap: _isAiSummaryMode ? _aiContextOverlap : 0,
      );

      // 6. Generate job definitions for backend
      final jobsForBackend = <Map<String, dynamic>>[];
      if (isAiBackendMode) {
        jobsForBackend.add({
          'id': const Uuid().v4(),
          'chunk_index': 0,
        });
      } else {
        for (int i = 0; i < totalChunks; i++) {
          final startSec = i * _segmentSeconds.toDouble();
          final durSec = (startSec + _segmentSeconds > safeVideoDuration)
              ? (safeVideoDuration - startSec)
              : _segmentSeconds.toDouble();

          jobsForBackend.add({
            'id': const Uuid().v4(),
            'chunk_index': i,
            // Other fields will be set by backend
          });
        }
      }

      // 7. Create project with all jobs on BACKEND in one transaction
      _logStep('Creating backend project with $totalChunks jobs...');
      final settingsPayload = settings.toJson();
      settingsPayload['category'] = _category;
      if (isAiBackendMode) {
        if (_processingMode == 'ai_best_scenes') {
          settingsPayload['summary_type'] = 'best_scenes';
        }
        settingsPayload['ai_best_scenes'] = aiOptions.toJson();
      }

      final backendResponse = await _runStep(
        'Create project with jobs',
        () => api.createProjectWithJobs(
          videoId: videoId,
          title: _selectedVideoFile!.name,
          totalChunks: totalChunks,
          jobs: jobsForBackend,
          settings: settingsPayload,
        ),
      );

      final backendProject = backendResponse['project'];
      final backendJobs = backendResponse['jobs'] as List;
      final backendProjectId = backendProject['id'] as String;

      _logStep(
          'Backend project ready | projectId=$backendProjectId | jobs=${backendJobs.length}');

      if (isAiBackendMode) {
        final jobId = backendJobs.first['id'] as String;
        await api.updateJob(
          jobId: jobId,
          status: 'pending',
          progress: 0.0,
          errorMessage: 'Queued for backend processing',
        );
        _logStep('AI job queued for backend worker | jobId=$jobId');

        // Close loading dialog and move user to project screen immediately.
        if (mounted) Navigator.pop(context);
        if (mounted) {
          final createdProject = Project.fromBackendMap(backendProject);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ProjectDetailScreen(project: createdProject),
            ),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI processing started in background.'),
              duration: Duration(seconds: 3),
            ),
          );
        }

        return;
      }

      // 8. Use selected video path directly (no pre-copy, faster start)
      // If user deletes/moves the source during processing, queue may fail.
      final localSourcePath = _selectedVideoPath!;
      _logStep('Split flow source path set: $localSourcePath');

      // 9. Create output directory
      final outputDir =
          await VideoQueueWorker.createOutputDirectory(backendProjectId);
      _logStep('Output directory created: $outputDir');

      // 10. Cache project locally in SQLite (for offline access & processing)
      await LocalQueueDb().cacheProject(
        id: backendProjectId,
        title: _selectedVideoFile!.name,
        sourceFilename: _selectedVideoFile!.name,
        localSourcePath: localSourcePath,
        localOutputDir: outputDir,
        settingsJson: jsonEncode(settings.toJson()),
        status: 'pending',
        totalChunks: totalChunks,
      );
      _logStep('Project cached in local DB');

      // 11. Cache jobs locally from backend response
      final localJobs = <ProcessingJob>[];
      for (var i = 0; i < backendJobs.length; i++) {
        final backendJob = backendJobs[i];
        final startSec = i * _segmentSeconds.toDouble();
        final durSec = (startSec + _segmentSeconds > safeVideoDuration)
            ? (safeVideoDuration - startSec)
            : _segmentSeconds.toDouble();

        final job = ProcessingJob(
          id: backendJob['id'],
          projectId: backendProjectId,
          chunkIndex: i,
          startSec: startSec,
          durationSec: durSec,
          status: JobStatus.pending,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        localJobs.add(job);
      }

      await LocalQueueDb().insertJobs(localJobs);
      _logStep('Jobs cached in local DB | count=${localJobs.length}');

      // 12. Start queue worker
      await VideoQueueWorker().start();
      _logStep('Queue worker started');

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (mounted) {
        final createdProject = Project.fromBackendMap(backendProject);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(project: createdProject),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Project "${createdProject.title}" created with $totalChunks clips'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) Navigator.pop(context);

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      _logStep('ERROR: $e');
    }
  }

  Future<void> _runAiBestScenesPipeline({
    required LocalBackendAPI api,
    required String jobId,
    required String projectId,
    required String inputVideoPath,
    required AiBestScenesOptions options,
  }) async {
    final aiService = AiBestScenesService();
    Future<void> markStep(String step,
        {required double progress, String status = 'running'}) async {
      _logStep('AI BG STEP: $step (${(progress * 100).toStringAsFixed(0)}%)');
      await api.updateJob(
        jobId: jobId,
        status: status,
        progress: progress,
        errorMessage: step,
      );
    }

    try {
      _logStep('AI BG: transcript preparation');
      final transcriptItems = await aiService
          .loadTranscriptSrtForVideo(
            videoPath: inputVideoPath,
            projectId: projectId,
            onStep: (step) {
              final lower = step.toLowerCase();
              if (lower.contains('extract')) {
                unawaited(markStep('Extract audio', progress: 0.1));
                return;
              }

              var progress = 0.2;
              final m = RegExp(r'chunk\s+(\d+)\s*/\s*(\d+)').firstMatch(lower);
              if (m != null) {
                final done = int.tryParse(m.group(1) ?? '') ?? 0;
                final total = int.tryParse(m.group(2) ?? '') ?? 1;
                final ratio = total <= 0
                    ? 0.0
                    : ((done / total).clamp(0.0, 1.0) as num).toDouble();
                progress = 0.11 + (0.09 * ratio);
              } else if (lower.contains('loading model')) {
                progress = 0.11;
              } else if (lower.contains('done')) {
                progress = 0.2;
              }

              unawaited(markStep(step, progress: progress));
            },
          )
          .timeout(const Duration(minutes: 20));
      await markStep(
        'Convert audio to text done | subtitle items=${transcriptItems.length}',
        progress: 0.2,
      );

      final chunks = aiService.chunkByItemCount(
        transcriptItems,
        chunkSize: options.srtChunkSize,
      );
      await markStep(
        'AI process text for best dialogs/scenes | chunks=${chunks.length}',
        progress: 0.25,
      );

      _logStep('AI BG: Bedrock analyze');
      final scenes = await aiService
          .askLlmAcrossChunks(
            projectId: projectId,
            chunks: chunks,
            options: options,
            onChunkProgress: ({
              required int chunkIndex,
              required int totalChunks,
              required int processedChunks,
              required int remainingChunks,
              required bool fromCache,
            }) {
              final ratio =
                  totalChunks == 0 ? 1.0 : processedChunks / totalChunks;
              final progress = 0.25 + (0.45 * ratio);
              final stepText = fromCache
                  ? 'AI process text chunk $processedChunks/$totalChunks (cache hit, remaining $remainingChunks)'
                  : 'AI process text chunk $processedChunks/$totalChunks (remaining $remainingChunks)';
              unawaited(markStep(stepText, progress: progress));
            },
          )
          .timeout(const Duration(minutes: 15));

      if (scenes.isEmpty) {
        throw Exception('AI could not detect best scenes from transcript');
      }

      await markStep('Segment best scenes', progress: 0.8);

      _logStep('AI BG: cutting scenes');
      final clipPaths = await aiService
          .cutScenesLocally(
            inputPath: inputVideoPath,
            scenes: scenes,
            projectId: projectId,
            onClipProgress: ({
              required int clipIndex,
              required int totalClips,
              required int processedClips,
              required int remainingClips,
            }) {
              final ratio = totalClips == 0 ? 1.0 : processedClips / totalClips;
              final progress = 0.80 + (0.10 * ratio);
              final stepText =
                  'Segment best scenes $processedClips/$totalClips (remaining $remainingClips)';
              unawaited(markStep(stepText, progress: progress));
            },
          )
          .timeout(const Duration(minutes: 25));

      await markStep('Merging final video', progress: 0.9);

      _logStep('AI BG: merging scenes');
      final finalOutputPath = await aiService
          .mergeScenes(
            clipPaths: clipPaths,
            projectId: projectId,
          )
          .timeout(const Duration(minutes: 20));
      final outputFilename = finalOutputPath.split('/').last;

      _logStep('AI BG STEP: Completed (100%)');
      await api.updateJob(
        jobId: jobId,
        status: 'completed',
        progress: 1.0,
        outputFilename: outputFilename,
        outputPath: finalOutputPath,
        errorMessage: null,
      );
      await api.registerOutputVideo(
        projectId: projectId,
        jobId: jobId,
        chunkIndex: 0,
        filename: outputFilename,
        filePath: finalOutputPath,
        durationSec: null,
        sizeBytes: await File(finalOutputPath).length(),
      );
      await api.updateProject(
        projectId: projectId,
        status: 'completed',
        completedChunks: 1,
        failedChunks: 0,
        progress: 1.0,
      );
      await GalleryExportService().saveVideoToGallery(finalOutputPath);
      _logStep('AI BG: pipeline complete');
    } catch (e) {
      _logStep('AI BG ERROR: $e');
      final err = e.toString();
      final friendly = err.contains('TimeoutException')
          ? 'AI step timed out on this device. Try shorter video or smaller chunk size.'
          : err;
      await api.updateJob(
        jobId: jobId,
        status: 'failed',
        errorMessage: friendly,
      );
      await api.updateProject(
        projectId: projectId,
        status: 'failed',
        failedChunks: 1,
      );
    }
  }

  // --- Step 1: Select Video ---
  Widget _stepSelectVideo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          _category == 'summary'
              ? 'Select video for AI Summary'
              : 'Select video to Split',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          _category == 'summary'
              ? 'Choose a video to create AI-powered summaries and highlights'
              : 'Choose a video to split into shorts with watermarks',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurface.withOpacity(0.65)),
        ),
        const SizedBox(height: 16),

        if (_selectedVideoPath != null)
          CfCard(
            child: ListTile(
              leading: const Icon(Icons.movie, size: 32),
              title: Text(
                _selectedVideoFile!.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Selected video'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedVideoFile = null;
                  _selectedVideoPath = null;
                  _selectedVideoBytes = null;
                }),
              ),
            ),
          )
        else
          CfCard(
            child: InkWell(
              onTap: () async {
                try {
                  if (!kIsWeb) {
                    final permissionService = PermissionService();
                    final granted =
                        await permissionService.requestVideoReadPermission();

                    if (!mounted) return;

                    if (!granted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Video permission is required to select videos'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                  }

                  PlatformFile? file;
                  if (kIsWeb) {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.video,
                      allowMultiple: false,
                      withData: true,
                    );
                    if (!mounted) return;
                    if (result == null || result.files.isEmpty) return;
                    file = result.files.single;
                  } else {
                    try {
                      final xfile = await _imagePicker.pickVideo(
                        source: ImageSource.gallery,
                      );
                      if (!mounted) return;
                      if (xfile == null) return;
                      final size = await File(xfile.path).length();
                      file = PlatformFile(
                        name: xfile.name,
                        path: xfile.path,
                        size: size,
                      );
                    } catch (_) {
                      // Some devices/OEM ROMs can fail with gallery activity results.
                      // Fallback to a generic video picker.
                      final fallback = await FilePicker.platform.pickFiles(
                        type: FileType.video,
                        allowMultiple: false,
                      );
                      if (!mounted) return;
                      if (fallback == null || fallback.files.isEmpty) return;
                      file = fallback.files.single;
                    }
                  }

                  setState(() {
                    _selectedVideoFile = file;
                    if (kIsWeb) {
                      _selectedVideoBytes = file!.bytes;
                      _selectedVideoPath = null;
                    } else {
                      _selectedVideoPath = file!.path;
                      _selectedVideoBytes = null;
                    }
                  });
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error selecting video: $e')),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(48.0),
                child: Column(
                  children: [
                    Icon(Icons.video_library, size: 64, color: cs.primary),
                    const SizedBox(height: 16),
                    Text('Tap to select video',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: cs.primary)),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Show selected video on THIS page (Step 1)
        if (_selectedVideoFile != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECTED VIDEO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedVideoFile!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedVideoFile = null;
                      _selectedVideoPath = null;
                      _selectedVideoBytes = null;
                    });
                  },
                  tooltip: 'Remove and select different video',
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Step 2: Processing Mode + Settings ---
  Widget _stepProcessingAndSettings(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Show selected video
        if (_selectedVideoFile != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.movie, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Video',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                      ),
                      Text(
                        _selectedVideoFile!.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Category Selection
        Text('What do you want to create?',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.category),
            hintText: 'Select category',
            filled: true,
            fillColor: cs.surfaceVariant.withOpacity(0.3),
          ),
          items: const [
            DropdownMenuItem(
              value: 'split',
              child: Row(
                children: [
                  Icon(Icons.content_cut, size: 20),
                  SizedBox(width: 12),
                  Text('Split Videos',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'summary',
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: Colors.purple),
                  SizedBox(width: 12),
                  Text('Create AI Summary',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _category = v;
                // Reset mode to first option of selected category
                if (v == 'split') {
                  _processingMode = 'split_only';
                } else {
                  _processingMode = 'ai_best_scenes';
                }
              });
            }
          },
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),

        // Processing Mode Section
        Text('Processing Mode',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),

        // Show Split modes ONLY when category is 'split'
        if (_category == 'split') ...[
          _ProcessingModeCard(
            context,
            title: 'Split Only',
            description: 'Split video into segments with watermark',
            icon: Icons.content_cut,
            selected: _processingMode == 'split_only',
            onTap: () => setState(() => _processingMode = 'split_only'),
          ),
          const SizedBox(height: 12),
          _ProcessingModeCard(
            context,
            title: 'AI Best Scenes (Clips)',
            description: 'AI finds best scenes and outputs multiple clips',
            icon: Icons.auto_awesome,
            selected: _processingMode == 'ai_best_scenes_split',
            onTap: () =>
                setState(() => _processingMode = 'ai_best_scenes_split'),
            footnote: '⚠️ Requires audio in video',
          ),
          const SizedBox(height: 12),
          _ProcessingModeCard(
            context,
            title: 'Split + Change Voice',
            description: 'Split and replace audio with TTS',
            icon: Icons.record_voice_over,
            selected: _processingMode == 'split_voice',
            onTap: () => setState(() => _processingMode = 'split_voice'),
          ),
          const SizedBox(height: 12),
          _ProcessingModeCard(
            context,
            title: 'Split + Translate',
            description: 'Split and translate to another language',
            icon: Icons.translate,
            selected: _processingMode == 'split_translate',
            onTap: () => setState(() => _processingMode = 'split_translate'),
          ),
        ],

        // Show Summary modes ONLY when category is 'summary'
        if (_category == 'summary') ...[
          _ProcessingModeCard(
            context,
            title: 'AI Best Scenes Only',
            description:
                'LLM finds best scenes and creates one highlight video',
            icon: Icons.auto_awesome,
            selected: _processingMode == 'ai_best_scenes',
            onTap: () => setState(() => _processingMode = 'ai_best_scenes'),
            footnote: '⚠️ Requires audio in video',
          ),
          const SizedBox(height: 12),
          _ProcessingModeCard(
            context,
            title: 'AI Summary + Original Audio',
            description: 'Best scenes with original audio/music + AI voiceover',
            icon: Icons.surround_sound,
            selected: _processingMode == 'ai_summary_hybrid',
            onTap: () => setState(() => _processingMode = 'ai_summary_hybrid'),
            footnote: '⚠️ Requires audio in video',
          ),
          const SizedBox(height: 12),
          _ProcessingModeCard(
            context,
            title: 'AI Story Only',
            description: 'Selected scenes with AI-generated narration audio',
            icon: Icons.mic,
            selected: _processingMode == 'ai_story_only',
            onTap: () => setState(() => _processingMode = 'ai_story_only'),
            footnote: '⚠️ Requires audio in video',
          ),
        ],

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),

        if (!_isAiBackendMode) ...[
          // Split settings are not used in AI Best Scenes mode
          Text('Split Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),

          Text('Segment Duration',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _segmentSeconds.toDouble(),
                  min: 30,
                  max: 120,
                  divisions: 9,
                  activeColor: cs.primary,
                  label: '$_segmentSeconds sec',
                  onChanged: (v) => setState(() => _segmentSeconds = v.toInt()),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withOpacity(0.3)),
                ),
                child: Text('$_segmentSeconds sec',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Text('Subscribe Overlay Duration',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Overlay appears in the last N seconds of each segment',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _subscribeSeconds.toDouble(),
                  min: 3,
                  max: 10,
                  divisions: 7,
                  activeColor: AppTheme.primary,
                  label: 'Last $_subscribeSeconds sec',
                  onChanged: (v) =>
                      setState(() => _subscribeSeconds = v.toInt()),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withOpacity(0.3)),
                ),
                child: Text('$_subscribeSeconds sec',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Text('App Watermark',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outline.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.branding_watermark, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your app logo will appear throughout the video (always enabled)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.8),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Logo Position',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _watermarkPosition,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.place),
              hintText: 'Select logo position',
            ),
            items: const [
              DropdownMenuItem(value: 'Top-left', child: Text('Top-left')),
              DropdownMenuItem(value: 'Top-right', child: Text('Top-right')),
              DropdownMenuItem(
                  value: 'Bottom-left', child: Text('Bottom-left')),
              DropdownMenuItem(
                  value: 'Bottom-right', child: Text('Bottom-right')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _watermarkPosition = v);
            },
          ),
        ],

        // Conditional: Voice Settings (Split + Voice mode)
        if (_processingMode == 'split_voice') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          Text('Voice Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text('Voice Style',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _voiceStyle,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.voice_chat),
              hintText: 'Select voice style',
            ),
            items: const [
              DropdownMenuItem(value: 'Natural', child: Text('Natural')),
              DropdownMenuItem(
                  value: 'Professional', child: Text('Professional')),
              DropdownMenuItem(
                  value: 'Conversational', child: Text('Conversational')),
              DropdownMenuItem(value: 'Energetic', child: Text('Energetic')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _voiceStyle = v);
            },
          ),
          const SizedBox(height: 20),
          Text('Speech Speed',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _voiceSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: cs.primary,
                  label: '${_voiceSpeed.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(
                      () => _voiceSpeed = double.parse(v.toStringAsFixed(1))),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withOpacity(0.3)),
                ),
                child: Text('${_voiceSpeed.toStringAsFixed(1)}x',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ],
          ),
        ],

        // Conditional: Translation Settings (Split + Translate mode)
        if (_processingMode == 'split_translate') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          Text('Translation Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text('Target Language',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _targetLanguage,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.language),
              hintText: 'Select target language',
            ),
            items: const [
              DropdownMenuItem(value: 'Spanish', child: Text('Spanish')),
              DropdownMenuItem(value: 'French', child: Text('French')),
              DropdownMenuItem(value: 'German', child: Text('German')),
              DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
              DropdownMenuItem(value: 'Arabic', child: Text('Arabic')),
              DropdownMenuItem(value: 'Chinese', child: Text('Chinese')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _targetLanguage = v);
            },
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Keep Original Audio'),
            subtitle: const Text(
                'Play translated subtitles with original audio track'),
            value: _keepOriginalAudio,
            onChanged: (v) => setState(() => _keepOriginalAudio = v),
          ),
        ],

        // Conditional: AI Mode Settings (All 3 AI modes)
        if (_processingMode == 'ai_best_scenes' ||
            _processingMode == 'ai_best_scenes_split' ||
            _processingMode == 'ai_summary_hybrid' ||
            _processingMode == 'ai_story_only') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          Text('AI Summary Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),

          Text('Output Language',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _aiLanguage,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.language),
              hintText: 'Select language for AI summary',
            ),
            items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'Spanish', child: Text('Spanish')),
              DropdownMenuItem(value: 'French', child: Text('French')),
              DropdownMenuItem(value: 'German', child: Text('German')),
              DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
              DropdownMenuItem(value: 'Arabic', child: Text('Arabic')),
              DropdownMenuItem(value: 'Chinese', child: Text('Chinese')),
              DropdownMenuItem(value: 'Portuguese', child: Text('Portuguese')),
              DropdownMenuItem(value: 'Japanese', child: Text('Japanese')),
              DropdownMenuItem(value: 'Korean', child: Text('Korean')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _aiLanguage = v);
            },
          ),

          const SizedBox(height: 20),

          Text('AI Voice',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _aiVoice,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.record_voice_over),
              hintText: 'Select AI voice',
            ),
            items: _voiceOptions
                .map(
                  (v) => DropdownMenuItem(
                    value: v['id'],
                    child: Text(_voiceLabel(v['id'] ?? '')),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _aiVoice = v);
            },
          ),
          if (_isAiSummaryMode) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _voiceLabel(_aiVoice),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _lastVoicePreview = _aiVoice;
                    _playVoicePreview(_aiVoice);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play sample'),
                ),
              ],
            ),
            Text(
              'Sample file: voice_${_aiVoice}.wav',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ],

          // Mode-specific info boxes
          const SizedBox(height: 20),
          if (_isAiBestScenesMode)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Flow: video -> audio -> SRT (local or backend whisper) -> Bedrock -> local split/merge',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
          if (_isAiBestScenesMode) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aiAddSubtitles,
              onChanged: (v) => setState(() => _aiAddSubtitles = v),
              title: const Text(
                'Add subtitles to final video',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Burn transcript subtitles into the merged highlight.',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Advanced Scene Tuning',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Tune key AI scene detection limits',
              ),
              trailing: Switch(
                value: _showAiAdvancedTuning,
                onChanged: (v) => setState(() => _showAiAdvancedTuning = v),
              ),
            ),
            if (_showAiAdvancedTuning) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _aiAutoChunk,
                onChanged: (v) => setState(() => _aiAutoChunk = v),
                title: const Text(
                  'Auto chunk size (max tokens)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'If off, you control how many subtitle lines go into each AI request.',
                ),
              ),
              if (!_aiAutoChunk) ...[
                Text(
                  'SRT Chunk Size: $_aiSrtChunkSize items',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: _aiSrtChunkSize.toDouble(),
                  min: 80,
                  max: 1200,
                  divisions: 56,
                  label: '$_aiSrtChunkSize',
                  onChanged: (v) => setState(() => _aiSrtChunkSize = v.round()),
                ),
                Text(
                  'Larger chunks give the model more context but take longer.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _aiAnySceneLength,
                onChanged: (v) => setState(() => _aiAnySceneLength = v),
                title: const Text(
                  'Allow long scenes (1–10 min)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Uses a wide 1–10 minute window.',
                ),
              ),
              if (!_aiAnySceneLength) ...[
                Text(
                  'Min Scene Duration: ${_aiMinSceneSec.toStringAsFixed(0)} sec',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: _aiMinSceneSec,
                  min: 8,
                  max: 40,
                  divisions: 32,
                  label: _aiMinSceneSec.toStringAsFixed(0),
                  onChanged: (v) => setState(() {
                    _aiMinSceneSec = v;
                    if (_aiMaxSceneSec < _aiMinSceneSec) {
                      _aiMaxSceneSec = _aiMinSceneSec;
                    }
                  }),
                ),
                const SizedBox(height: 10),
                Text(
                  'Max Scene Duration: ${_aiMaxSceneSec.toStringAsFixed(0)} sec',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: _aiMaxSceneSec,
                  min: 20,
                  max: 120,
                  divisions: 40,
                  label: _aiMaxSceneSec.toStringAsFixed(0),
                  onChanged: (v) => setState(() {
                    _aiMaxSceneSec = v;
                    if (_aiMinSceneSec > _aiMaxSceneSec) {
                      _aiMinSceneSec = _aiMaxSceneSec;
                    }
                  }),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Score Threshold: $_aiScoreThreshold',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _aiScoreThreshold.toDouble(),
                min: 50,
                max: 95,
                divisions: 45,
                label: _aiScoreThreshold.toString(),
                onChanged: (v) => setState(() => _aiScoreThreshold = v.round()),
              ),
              const SizedBox(height: 10),
              Text(
                'Min Gap Between Scenes: ${_aiMinGapSec.toStringAsFixed(1)} sec',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _aiMinGapSec,
                min: 0,
                max: 8,
                divisions: 16,
                label: _aiMinGapSec.toStringAsFixed(1),
                onChanged: (v) => setState(
                    () => _aiMinGapSec = double.parse(v.toStringAsFixed(1))),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _aiSegmentsPerChunk,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.tune),
                  labelText: 'Segments per Chunk',
                  helperText:
                      'How many candidate scenes the AI proposes per chunk.',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 4, child: Text('4')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _aiSegmentsPerChunk = v);
                },
              ),
            ],
          ],
          if (_processingMode == 'ai_summary_hybrid')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Summary mixes original audio/music with AI storytelling',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
          if (_processingMode == 'ai_story_only')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI generates complete story narration with selected scenes',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
          if (_isAiSummaryMode) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aiAutoChunk,
              onChanged: (v) => setState(() => _aiAutoChunk = v),
              title: const Text(
                'Auto chunk by token budget',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'If off, you control how many subtitle lines go into each AI request.',
              ),
            ),
            if (!_aiAutoChunk) ...[
              Text(
                'SRT Chunk Size: $_aiSrtChunkSize items',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _aiSrtChunkSize.toDouble(),
                min: 80,
                max: 1200,
                divisions: 56,
                label: '$_aiSrtChunkSize',
                onChanged: (v) => setState(() => _aiSrtChunkSize = v.round()),
              ),
              Text(
                'Larger chunks give the model more context but take longer.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Context Overlap: $_aiContextOverlap lines',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: _aiContextOverlap.toDouble(),
              min: 0,
              max: 30,
              divisions: 30,
              label: '$_aiContextOverlap',
              onChanged: (v) => setState(() => _aiContextOverlap = v.round()),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _summaryPlanOnly,
              onChanged: (v) => setState(() => _summaryPlanOnly = v),
              title: const Text(
                'Review scenes before render',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Stops after analysis so you can pick scenes before rendering.',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _summarySegmentsPerChunk,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.tune),
                labelText: 'Segments per Chunk',
                helperText: 'How many summary segments to take from each chunk.',
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 2, child: Text('2')),
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 4, child: Text('4')),
                DropdownMenuItem(value: 5, child: Text('5')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _summarySegmentsPerChunk = v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _summaryMaxSegments == 0
                  ? 'Max Total Segments: Unlimited'
                  : 'Max Total Segments: $_summaryMaxSegments',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: _summaryMaxSegments.toDouble(),
              min: 0,
              max: 60,
              divisions: 60,
              label: _summaryMaxSegments == 0
                  ? 'Unlimited'
                  : _summaryMaxSegments.toString(),
              onChanged: (v) =>
                  setState(() => _summaryMaxSegments = v.round()),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Advanced Narration Tuning',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('TTS speed fit, fade and mix'),
              trailing: Switch(
                value: _showAiSummaryTuning,
                onChanged: (v) => setState(() => _showAiSummaryTuning = v),
              ),
            ),
            if (_showAiSummaryTuning) ...[
              if (_processingMode == 'ai_summary_hybrid') ...[
                _LabeledSlider(
                  label: 'Duck Volume',
                  value: _ttsDuckVolume,
                  min: 0.1,
                  max: 0.5,
                  divisions: 8,
                  onChanged: (v) => setState(() => _ttsDuckVolume = v),
                  suffix: _ttsDuckVolume.toStringAsFixed(2),
                  helper:
                      'Lower = more original audio reduction under narration.',
                ),
              ],
              _LabeledSlider(
                label: 'Max Speedup',
                value: _ttsMaxSpeedup,
                min: 1.0,
                max: 1.8,
                divisions: 8,
                onChanged: (v) => setState(() => _ttsMaxSpeedup = v),
                suffix: '${_ttsMaxSpeedup.toStringAsFixed(2)}x',
              ),
              _LabeledSlider(
                label: 'Min Slowdown',
                value: _ttsMinSlowdown,
                min: 0.6,
                max: 1.0,
                divisions: 8,
                onChanged: (v) => setState(() => _ttsMinSlowdown = v),
                suffix: '${_ttsMinSlowdown.toStringAsFixed(2)}x',
              ),
              _LabeledSlider(
                label: 'TTS Fade',
                value: _ttsFadeSec,
                min: 0.05,
                max: 0.3,
                divisions: 10,
                onChanged: (v) => setState(() => _ttsFadeSec = v),
                suffix: '${_ttsFadeSec.toStringAsFixed(2)}s',
              ),
            ],
          ],
        ],
      ],
    );
  }

  // --- Step 3: Review ---
  Widget _stepReview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String modeName = _processingMode == 'split_only'
        ? 'Split Only'
        : _processingMode == 'split_voice'
            ? 'Split + Change Voice'
            : _processingMode == 'split_translate'
                ? 'Split + Translate'
                : _processingMode == 'ai_best_scenes'
                    ? 'AI Best Scenes Only'
                    : _processingMode == 'ai_best_scenes_split'
                        ? 'AI Best Scenes (Clips)'
                        : _processingMode == 'ai_summary_hybrid'
                            ? 'AI Summary + Original Audio'
                            : 'AI Story Only';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Review Settings',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Review your configuration before exporting',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 24),
        CfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewItem(
                  label: 'Video', value: _selectedVideoFile?.name ?? 'None'),
              const Divider(),
              _ReviewItem(label: 'Processing Mode', value: modeName),
              const Divider(),
              if (!_isAiBackendMode) ...[
                _ReviewItem(
                    label: 'Segment Duration',
                    value: '$_segmentSeconds seconds'),
                const Divider(),
                _ReviewItem(
                    label: 'Subscribe Overlay',
                    value: 'Last $_subscribeSeconds seconds'),
                const Divider(),
                _ReviewItem(
                    label: 'Watermark Position', value: _watermarkPosition),
              ],
              if (_processingMode == 'split_voice') ...[
                const Divider(),
                _ReviewItem(label: 'Voice Style', value: _voiceStyle),
                const Divider(),
                _ReviewItem(
                    label: 'Speech Speed',
                    value: '${_voiceSpeed.toStringAsFixed(1)}x'),
              ],
              if (_processingMode == 'split_translate') ...[
                const Divider(),
                _ReviewItem(label: 'Target Language', value: _targetLanguage),
                const Divider(),
                _ReviewItem(
                    label: 'Keep Original Audio',
                    value: _keepOriginalAudio ? 'Yes' : 'No'),
              ],
              if (_processingMode == 'ai_best_scenes' ||
                  _processingMode == 'ai_best_scenes_split' ||
                  _processingMode == 'ai_summary_hybrid' ||
                  _processingMode == 'ai_story_only') ...[
                const Divider(),
                _ReviewItem(label: 'AI Language', value: _aiLanguage),
                const Divider(),
                _ReviewItem(label: 'AI Voice', value: _voiceLabel(_aiVoice)),
              ],
              if (_isAiBestScenesMode) ...[
                if (!_aiAutoChunk) ...[
                  const Divider(),
                  _ReviewItem(
                      label: 'SRT Chunk Size', value: '$_aiSrtChunkSize items'),
                ],
                if (!_aiAnySceneLength) ...[
                  const Divider(),
                  _ReviewItem(
                      label: 'Scene Duration',
                      value:
                          '${_aiMinSceneSec.toStringAsFixed(0)}-${_aiMaxSceneSec.toStringAsFixed(0)} sec'),
                ],
                const Divider(),
                _ReviewItem(
                    label: 'Score Threshold',
                    value: _aiScoreThreshold.toString()),
                const Divider(),
                _ReviewItem(
                    label: 'Min Scene Gap',
                    value: '${_aiMinGapSec.toStringAsFixed(1)} sec'),
                const Divider(),
                _ReviewItem(
                    label: 'Segments per Chunk',
                    value: _aiSegmentsPerChunk.toString()),
              ],
              if (_isAiSummaryMode) ...[
                if (!_aiAutoChunk) ...[
                  const Divider(),
                  _ReviewItem(
                      label: 'SRT Chunk Size',
                      value: '$_aiSrtChunkSize items'),
                ],
                const Divider(),
                _ReviewItem(
                    label: 'Context Overlap',
                    value: '$_aiContextOverlap lines'),
                const Divider(),
                _ReviewItem(
                    label: 'Review Scenes First',
                    value: _summaryPlanOnly ? 'Yes' : 'No'),
                const Divider(),
                _ReviewItem(
                    label: 'Segments per Chunk',
                    value: _summarySegmentsPerChunk.toString()),
                const Divider(),
                _ReviewItem(
                    label: 'Max Total Segments',
                    value:
                        _summaryMaxSegments == 0
                            ? 'Unlimited'
                            : _summaryMaxSegments.toString()),
                if (_processingMode == 'ai_summary_hybrid') ...[
                  const Divider(),
                  _ReviewItem(
                      label: 'Duck Volume',
                      value: _ttsDuckVolume.toStringAsFixed(2)),
                ],
                const Divider(),
                _ReviewItem(
                    label: 'Max Speedup',
                    value: '${_ttsMaxSpeedup.toStringAsFixed(2)}x'),
                const Divider(),
                _ReviewItem(
                    label: 'Min Slowdown',
                    value: '${_ttsMinSlowdown.toStringAsFixed(2)}x'),
                const Divider(),
                _ReviewItem(
                    label: 'TTS Fade',
                    value: '${_ttsFadeSec.toStringAsFixed(2)}s'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 4: Export/Share ---
  Widget _stepExportShare(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Export & Share',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose how to export your shorts',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 24),
        CheckboxListTile(
          title: const Text('Save Locally',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Save to your device'),
          secondary: const Icon(Icons.folder),
          value: _exportLocal,
          onChanged: (v) => setState(() => _exportLocal = v ?? true),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        Text('Push to Social Media',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Connect and share directly (requires OAuth)',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 16),
        CheckboxListTile(
          title: const Text('YouTube Shorts'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.play_circle_outline),
          value: _socialMediaTargets['youtube']!,
          enabled: false,
          onChanged: (v) =>
              setState(() => _socialMediaTargets['youtube'] = v ?? false),
        ),
        CheckboxListTile(
          title: const Text('Instagram Reels'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.camera_alt),
          value: _socialMediaTargets['instagram']!,
          enabled: false,
          onChanged: (v) =>
              setState(() => _socialMediaTargets['instagram'] = v ?? false),
        ),
        CheckboxListTile(
          title: const Text('TikTok'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.music_note),
          value: _socialMediaTargets['tiktok']!,
          enabled: false,
          onChanged: (v) =>
              setState(() => _socialMediaTargets['tiktok'] = v ?? false),
        ),
        CheckboxListTile(
          title: const Text('Facebook Reels'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.facebook),
          value: _socialMediaTargets['facebook']!,
          enabled: false,
          onChanged: (v) =>
              setState(() => _socialMediaTargets['facebook'] = v ?? false),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Social media connection coming soon!')),
            );
          },
          icon: const Icon(Icons.add_link),
          label: const Text('Connect More Accounts'),
        ),
      ],
    );
  }

  // Helper widget for processing mode cards
  Widget _ProcessingModeCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    String? footnote, // Optional footnote for warnings
  }) {
    final cs = Theme.of(context).colorScheme;
    return CfCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          selected ? cs.primary : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: selected ? Colors.white : Colors.grey[600],
                        size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(description,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: cs.primary, size: 28),
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    footnote,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for review items
  Widget _ReviewItem({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.suffix,
    this.helper,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          suffix == null ? label : '$label: $suffix',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: suffix,
          onChanged: onChanged,
          activeColor: cs.primary,
        ),
        if (helper != null)
          Text(
            helper!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
