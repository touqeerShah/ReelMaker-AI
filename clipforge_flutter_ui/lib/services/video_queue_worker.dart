import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/processing_job.dart';
import '../models/video_project.dart';
import '../models/output_video.dart';
import 'local_queue_db.dart';
import 'ffmpeg_processor.dart';
import 'local_backend_api.dart';
import 'gallery_export_service.dart';

/// Background worker that processes video chunks sequentially
/// Processes one job at a time to avoid overwhelming the device
class VideoQueueWorker {
  static VideoQueueWorker? _instance;
  bool _isRunning = false;
  bool _shouldStop = false;
  Timer? _pollTimer;

  // Singleton instance
  VideoQueueWorker._();

  factory VideoQueueWorker() {
    _instance ??= VideoQueueWorker._();
    return _instance!;
  }

  bool get isRunning => _isRunning;

  /// Start the queue worker
  Future<void> start() async {
    if (_isRunning) {
      print('[VideoQueueWorker] Already running');
      return;
    }

    print('[VideoQueueWorker] Starting queue worker');
    _isRunning = true;
    _shouldStop = false;

    // Start processing loop
    _processQueue();
  }

  /// Stop the queue worker
  Future<void> stop() async {
    print('[VideoQueueWorker] Stopping queue worker');
    _shouldStop = true;
    _pollTimer?.cancel();
    _isRunning = false;
  }

  /// Main processing loop - polls for pending jobs
  Future<void> _processQueue() async {
    while (_isRunning && !_shouldStop) {
      try {
        // Get next pending job from local database
        final job = await LocalQueueDb().getNextPendingJob();

        if (job == null) {
          // No pending jobs, wait before checking again
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        // Process this job
        await _processJob(job);
      } catch (e) {
        print('[VideoQueueWorker] Error in processing loop: $e');
        await Future.delayed(const Duration(seconds: 5)); // Wait before retry
      }
    }

    print('[VideoQueueWorker] Processing loop ended');
    _isRunning = false;
  }

  /// Process a single job
  Future<void> _processJob(ProcessingJob job) async {
    print(
        '[VideoQueueWorker] Processing job: ${job.id} (chunk ${job.chunkIndex})');

    try {
      // Update job status to RUNNING locally
      await LocalQueueDb().updateJobStatus(
        job.id,
        JobStatus.running,
        processingStartedAt: DateTime.now(),
      );

      // Sync running status to local backend (used by Queue tab)
      await _syncJobStatusToBackend(
        jobId: job.id,
        status: 'running',
        progress: 0.0,
      );

      // Sync to Supabase
      await _syncJobToSupabase(job.copyWith(
        status: JobStatus.running,
        processingStartedAt: DateTime.now(),
      ));

      // Load project details from cache
      final projectCache = await LocalQueueDb().getCachedProject(job.projectId);
      if (projectCache == null) {
        throw Exception('Project ${job.projectId} not found in cache');
      }

      // Build paths with new naming pattern: {originalName}_001.mp4, etc.
      final outputDir = projectCache['local_output_dir'] as String;
      final sourceFilename = projectCache['source_filename'] as String;
      final outputFilename =
          OutputVideo.generateFilename(sourceFilename, job.chunkIndex);
      final outputPath = '$outputDir/$outputFilename';

      // Get watermark path
      final watermarkPath = await _getWatermarkPath();

      // Get project settings
      final settingsJson = projectCache['settings_json'] as String;
      final settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;
      final settings = ProjectSettings.fromJson(settingsMap);

      // Process with FFmpeg
      print(
          '[VideoQueueWorker] Processing chunk ${job.chunkIndex}: ${job.startSec}s for ${job.durationSec}s');

      final result = await FFmpegProcessor().processChunk(
        inputPath: projectCache['local_source_path'] as String,
        outputPath: outputPath,
        startSec: job.startSec,
        durationSec: job.durationSec,
        watermarkPath: watermarkPath,
        channelName: settings.channelName,
        flipMode: settings.flipMode,
        randomTextPosition: settings.textRandomPosition,
        watermarkPosition: settings.watermarkPosition,
        watermarkAlpha: settings.watermarkAlpha,
        onProgress: (progress) async {
          // Update progress in local DB
          await LocalQueueDb().updateJobStatus(
            job.id,
            JobStatus.running,
            progress: progress,
          );

          // Sync progress to Supabase (throttled - every 10%)
          if ((progress * 100).toInt() % 10 == 0) {
            await _syncJobProgressToSupabase(job.id, progress);
            await _syncJobStatusToBackend(
              jobId: job.id,
              status: 'running',
              progress: progress,
            );
          }
        },
      );

      if (result.isSuccess) {
        // Mark as completed
        await LocalQueueDb().markJobAsCompleted(job.id, outputFilename);
        await _syncJobCompletionToSupabase(job.id, outputFilename);
        await _syncJobStatusToBackend(
          jobId: job.id,
          status: 'completed',
          progress: 1.0,
          outputFilename: outputFilename,
          outputPath: outputPath,
        );

        // Register output video with backend
        await _registerOutputWithBackend(
          projectId: job.projectId,
          jobId: job.id,
          chunkIndex: job.chunkIndex,
          filename: outputFilename,
          filePath: outputPath,
          durationSec: job.durationSec,
        );

        // Copy output to gallery so user can see result in Photos/Gallery app
        final saved =
            await GalleryExportService().saveVideoToGallery(outputPath);
        if (saved) {
          print('[VideoQueueWorker] Saved output to gallery: $outputFilename');
        } else {
          print(
              '[VideoQueueWorker] Could not save output to gallery (permission or platform)');
        }

        print('[VideoQueueWorker] Job ${job.id} completed successfully');
      } else {
        // Mark as failed
        final error = result.error ?? 'Unknown error';
        await LocalQueueDb().markJobAsFailed(job.id, error);
        await _syncJobFailureToSupabase(job.id, error);
        await _syncJobStatusToBackend(
          jobId: job.id,
          status: 'failed',
          progress: 0.0,
          errorMessage: error,
        );

        print('[VideoQueueWorker] Job ${job.id} failed: $error');
      }
    } catch (e) {
      print('[VideoQueueWorker] Exception processing job ${job.id}: $e');

      // Mark as failed
      await LocalQueueDb().markJobAsFailed(job.id, e.toString());
      await _syncJobFailureToSupabase(job.id, e.toString());
      await _syncJobStatusToBackend(
        jobId: job.id,
        status: 'failed',
        progress: 0.0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Get watermark image path from assets or storage
  /// Returns null if watermark should not be used
  Future<String?> _getWatermarkPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final watermarkPath = '${appDir.path}/watermark.png';
    final watermarkFile = File(watermarkPath);

    // Check if watermark already exists in app storage
    if (await watermarkFile.exists()) {
      return watermarkPath;
    }

    // Try to copy from assets
    try {
      // Load watermark from assets
      final ByteData data =
          await rootBundle.load('assets/images/watermark.png');
      final List<int> bytes = data.buffer.asUint8List();

      // Write to app storage
      await watermarkFile.writeAsBytes(bytes);

      print(
          '[VideoQueueWorker] Watermark copied from assets to $watermarkPath');
      return watermarkPath;
    } catch (e) {
      // Asset doesn't exist or couldn't be loaded
      print(
          '[VideoQueueWorker] No watermark found, processing without watermark: $e');
      return null;
    }
  }

  // ============================================================
  // SUPABASE SYNC METHODS (Optional - only if Supabase is initialized)
  // ============================================================

  /// Check if Supabase is available
  bool _isSupabaseAvailable() {
    try {
      // Try to access Supabase instance
      final _ = Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync job to Supabase
  Future<void> _syncJobToSupabase(ProcessingJob job) async {
    if (!_isSupabaseAvailable()) {
      // Supabase not initialized, skip sync
      return;
    }

    try {
      await Supabase.instance.client
          .from('processing_jobs')
          .upsert(job.toSupabaseMap());
    } catch (e) {
      print('[VideoQueueWorker] Error syncing job to Supabase: $e');
      // Don't throw - local processing continues even if sync fails
    }
  }

  /// Sync job progress to Supabase
  Future<void> _syncJobProgressToSupabase(String jobId, double progress) async {
    if (!_isSupabaseAvailable()) return;

    try {
      await Supabase.instance.client.from('processing_jobs').update({
        'progress': progress,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', jobId);
    } catch (e) {
      print('[VideoQueueWorker] Error syncing progress: $e');
    }
  }

  /// Sync job completion to Supabase
  Future<void> _syncJobCompletionToSupabase(
      String jobId, String outputFilename) async {
    if (!_isSupabaseAvailable()) return;

    try {
      await Supabase.instance.client.from('processing_jobs').update({
        'status': 'completed',
        'output_filename': outputFilename,
        'processing_completed_at': DateTime.now().toIso8601String(),
        'progress': 1.0,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', jobId);
    } catch (e) {
      print('[VideoQueueWorker] Error syncing completion: $e');
    }
  }

  /// Sync job failure to Supabase
  Future<void> _syncJobFailureToSupabase(String jobId, String error) async {
    if (!_isSupabaseAvailable()) return;

    try {
      await Supabase.instance.client.from('processing_jobs').update({
        'status': 'failed',
        'error_message': error,
        'processing_completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', jobId);
    } catch (e) {
      print('[VideoQueueWorker] Error syncing failure: $e');
    }
  }

  /// Register output video with backend API
  Future<void> _registerOutputWithBackend({
    required String projectId,
    required String jobId,
    required int chunkIndex,
    required String filename,
    required String filePath,
    double? durationSec,
  }) async {
    try {
      final api = LocalBackendAPI();
      if (!api.isAuthenticated) {
        print(
            '[VideoQueueWorker] Not authenticated, skipping output registration');
        return;
      }

      // Get file size
      final file = File(filePath);
      final sizeBytes = await file.exists() ? await file.length() : null;

      await api.registerOutputVideo(
        projectId: projectId,
        jobId: jobId,
        chunkIndex: chunkIndex,
        filename: filename,
        filePath: filePath,
        durationSec: durationSec,
        sizeBytes: sizeBytes,
      );

      print('[VideoQueueWorker] Registered output video: $filename');
    } catch (e) {
      print('[VideoQueueWorker] Error registering output with backend: $e');

      // Retry once using project_id resolved from backend job (handles stale local project ids)
      if (e.toString().contains('Project not found')) {
        try {
          final api = LocalBackendAPI();
          final backendJob = await api.getJob(jobId);
          final resolvedProjectId = backendJob['project_id']?.toString();

          if (resolvedProjectId != null && resolvedProjectId.isNotEmpty) {
            await api.registerOutputVideo(
              projectId: resolvedProjectId,
              jobId: jobId,
              chunkIndex: chunkIndex,
              filename: filename,
              filePath: filePath,
              durationSec: durationSec,
              sizeBytes: File(filePath).existsSync()
                  ? File(filePath).lengthSync()
                  : null,
            );
            print(
                '[VideoQueueWorker] Registered output video after resolving project id: $filename');
            return;
          }
        } catch (retryError) {
          print('[VideoQueueWorker] Retry register output failed: $retryError');
        }
      }
      // Don't throw - local processing continues even if backend registration fails
    }
  }

  /// Sync job status/progress to local backend queue table
  Future<void> _syncJobStatusToBackend({
    required String jobId,
    required String status,
    double? progress,
    String? errorMessage,
    String? outputFilename,
    String? outputPath,
  }) async {
    try {
      final api = LocalBackendAPI();
      if (!api.isAuthenticated) return;

      await api.updateJob(
        jobId: jobId,
        status: status,
        progress: progress,
        errorMessage: errorMessage,
        outputFilename: outputFilename,
        outputPath: outputPath,
      );
    } catch (e) {
      print('[VideoQueueWorker] Error syncing job to backend: $e');
    }
  }

  /// Create project in Supabase
  static Future<VideoProject> createProject({
    required String userId,
    required String title,
    required String sourceFilename,
    double? sourceDurationSec,
    String? sourceResolution,
    required ProjectSettings settings,
    required int totalChunks,
  }) async {
    final project = VideoProject(
      id: '', // Will be generated by Supabase
      userId: userId,
      title: title,
      sourceFilename: sourceFilename,
      sourceDurationSec: sourceDurationSec,
      sourceResolution: sourceResolution,
      settings: settings,
      status: ProjectStatus.pending,
      totalChunks: totalChunks,
      completedChunks: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final response = await Supabase.instance.client
        .from('projects')
        .insert(project.toSupabaseMap())
        .select()
        .single();

    return VideoProject.fromSupabaseMap(response);
  }

  /// Copy video to app storage
  static Future<String> copyVideoToAppStorage(
      String projectId, String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/$projectId');

    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final sourceFile = File(sourcePath);
    final targetPath =
        '${projectDir.path}/input${_getFileExtension(sourcePath)}';

    await sourceFile.copy(targetPath);
    return targetPath;
  }

  /// Create output directory for project
  static Future<String> createOutputDirectory(String projectId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${appDir.path}/projects/$projectId/clips');

    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    return outputDir.path;
  }

  /// Get file extension from path
  static String _getFileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '.mp4';
    return path.substring(lastDot);
  }
}
