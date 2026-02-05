import 'package:flutter/material.dart';

enum ProjectStatus { draft, processing, completed, failed }

enum JobStage {
  queued,
  paused,
  extractingAudio,
  transcribing,
  translating,
  dubbing,
  rendering,
  completed,
  failed,
}

class Project {
  Project({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.duration,
    required this.status,
    required this.thumbnail,
    required this.shortsCount,
    required this.languages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final ProjectStatus status;
  final String thumbnail;
  final int shortsCount;
  final List<String> languages;

  /// Create Project from backend API response
  factory Project.fromBackendMap(Map<String, dynamic> json) {
    // Map backend status to UI status
    ProjectStatus status = ProjectStatus.draft;
    final statusStr = json['status']?.toString().toLowerCase() ?? 'draft';
    if (statusStr.contains('process')) {
      status = ProjectStatus.processing;
    } else if (statusStr.contains('complet')) {
      status = ProjectStatus.completed;
    } else if (statusStr.contains('fail')) {
      status = ProjectStatus.failed;
    }

    // Calculate duration from backend shape (snake_case) with camelCase fallback
    final durationRaw = json['duration_sec'] ??
        json['durationSec'] ??
        json['video']?['durationSec'] ??
        0.0;
    final duration = Duration(seconds: (durationRaw as num).toInt());

    // Get completed chunk count (snake_case + camelCase fallback)
    final completedChunks =
        (json['completed_chunks'] ?? json['completedChunks'] ?? 0) as int;

    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final createdAt = createdAtRaw != null
        ? DateTime.parse(createdAtRaw.toString())
        : DateTime.now();

    return Project(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      createdAt: createdAt,
      duration: duration,
      status: status,
      thumbnail:
          'https://images.unsplash.com/photo-1525182008055-f88b95ff7980?w=800&q=80',
      shortsCount: completedChunks,
      languages: const ['EN'], // Default, could be extended from settings
    );
  }
}

class Job {
  Job({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.stage,
    required this.progress,
    required this.elapsed,
    this.speed = 1.0,
    this.eta,
    this.hasDeviceHotWarning = false,
    this.hasLowBatteryWarning = false,
    this.projectId,
    this.chunkIndex,
    this.outputFilename,
    this.outputPath,
    this.backendStatus,
    this.stepMessage,
  });

  final String id;
  final String title;
  final String thumbnail;
  final JobStage stage;
  final double progress; // 0..1
  final Duration elapsed;
  final double speed;
  final Duration? eta;
  final bool hasDeviceHotWarning;
  final bool hasLowBatteryWarning;
  final String? projectId;
  final int? chunkIndex;
  final String? outputFilename;
  final String? outputPath;
  final String? backendStatus;
  final String? stepMessage;

  /// Create Job from backend API response
  factory Job.fromBackendMap(Map<String, dynamic> json) {
    // Map backend status to UI JobStage
    JobStage stage = JobStage.queued;
    final statusStr = json['status']?.toString().toLowerCase() ?? 'pending';

    if (statusStr == 'pending') {
      stage = JobStage.queued;
    } else if (statusStr == 'paused') {
      stage = JobStage.paused;
    } else if (statusStr == 'running') {
      // Map to rendering since we're doing video processing
      stage = JobStage.rendering;
    } else if (statusStr == 'completed') {
      stage = JobStage.completed;
    } else if (statusStr == 'failed') {
      stage = JobStage.failed;
    }

    // Calculate elapsed time
    Duration elapsed = Duration.zero;
    final startedAtRaw = json['started_at'] ??
        json['processing_started_at'] ??
        json['processingStartedAt'];
    final completedAtRaw = json['completed_at'] ??
        json['processing_completed_at'] ??
        json['processingCompletedAt'];
    if (startedAtRaw != null) {
      final startedAt = DateTime.parse(startedAtRaw.toString());
      final endTime = completedAtRaw != null
          ? DateTime.parse(completedAtRaw.toString())
          : DateTime.now();
      elapsed = endTime.difference(startedAt);
    }

    // Get progress
    final progress = (json['progress'] as num?)?.toDouble() ?? 0.0;

    // Get project/video title for the job
    final chunkIndex = (json['chunk_index'] ?? json['chunkIndex'] ?? 0) as int;
    final projectTitle = json['project_title']?.toString() ??
        json['projectTitle']?.toString() ??
        '';
    final projectId = json['project_id'] ?? json['projectId'] ?? '';
    final title = projectTitle.isNotEmpty
        ? '$projectTitle • ${chunkIndex + 1}'
        : 'Chunk #${chunkIndex + 1} - $projectId';
    final outputPath =
        json['output_path']?.toString() ?? json['outputPath']?.toString();

    return Job(
      id: json['id'] ?? '',
      title: title,
      thumbnail: (statusStr == 'completed' &&
              outputPath != null &&
              outputPath.isNotEmpty)
          ? outputPath
          : 'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?w=1000&q=80',
      stage: stage,
      progress: progress,
      elapsed: elapsed,
      speed: 1.0, // Not tracked in backend yet
      eta: null, // Could calculate from progress if needed
      projectId: projectId.toString(),
      chunkIndex: chunkIndex,
      outputFilename: json['output_filename']?.toString() ??
          json['outputFilename']?.toString(),
      outputPath: outputPath,
      backendStatus: statusStr,
      stepMessage:
          json['error_message']?.toString() ?? json['errorMessage']?.toString(),
    );
  }
}

class ModelAsset {
  ModelAsset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.sizeLabel,
    required this.icon,
    required this.status,
  });

  final String id;
  final String name;
  final String subtitle;
  final String sizeLabel;
  final IconData icon;
  final ModelStatus status;
}

enum ModelStatus { notInstalled, downloading, ready, updateAvailable }

String projectStatusLabel(ProjectStatus s) => switch (s) {
      ProjectStatus.draft => 'Draft',
      ProjectStatus.processing => 'Processing',
      ProjectStatus.completed => 'Completed',
      ProjectStatus.failed => 'Failed',
    };

Color projectStatusColor(ProjectStatus s, ColorScheme cs) => switch (s) {
      ProjectStatus.draft => cs.outline,
      ProjectStatus.processing => cs.primary,
      ProjectStatus.completed => Colors.green,
      ProjectStatus.failed => Colors.red,
    };

String jobStageLabel(JobStage s) => switch (s) {
      JobStage.queued => 'Queued',
      JobStage.paused => 'Paused',
      JobStage.extractingAudio => 'Extracting audio',
      JobStage.transcribing => 'Transcribing',
      JobStage.translating => 'Translating',
      JobStage.dubbing => 'Dubbing',
      JobStage.rendering => 'Rendering',
      JobStage.completed => 'Completed',
      JobStage.failed => 'Failed',
    };
