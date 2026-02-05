import 'dart:convert';

enum ProjectStatus {
  pending,
  processing,
  completed,
  failed;

  static ProjectStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return ProjectStatus.pending;
      case 'processing':
        return ProjectStatus.processing;
      case 'completed':
        return ProjectStatus.completed;
      case 'failed':
        return ProjectStatus.failed;
      default:
        return ProjectStatus.pending;
    }
  }

  String toJson() => name;
}

class ProjectSettings {
  final String category; // split, summary
  final int segmentSeconds;
  final bool watermarkEnabled;
  final String
      watermarkPosition; // top_left, top_right, bottom_left, bottom_right
  final double watermarkAlpha;
  final bool subtitlesEnabled;
  final String channelName;
  final bool textRandomPosition;
  final String flipMode; // none, hflip, vflip
  final String outputResolution; // e.g., "1080x1920"
  final String processingMode; // split_only, split_voice, split_translate, ai_*

  ProjectSettings({
    this.category = 'split',
    this.segmentSeconds = 60,
    this.watermarkEnabled = true,
    this.watermarkPosition = 'bottom_right',
    this.watermarkAlpha = 0.55,
    this.subtitlesEnabled = false,
    required this.channelName,
    this.textRandomPosition = true,
    this.flipMode = 'none',
    this.outputResolution = '1080x1920',
    this.processingMode = 'split_only',
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'segment_seconds': segmentSeconds,
      'watermark_enabled': watermarkEnabled,
      'watermark_position': watermarkPosition,
      'watermark_alpha': watermarkAlpha,
      'subtitles_enabled': subtitlesEnabled,
      'channel_name': channelName,
      'text_random_position': textRandomPosition,
      'flip_mode': flipMode,
      'output_resolution': outputResolution,
      'processing_mode': processingMode,
    };
  }

  factory ProjectSettings.fromJson(Map<String, dynamic> json) {
    return ProjectSettings(
      category: json['category'] as String? ?? 'split',
      segmentSeconds: json['segment_seconds'] as int? ?? 60,
      watermarkEnabled: json['watermark_enabled'] as bool? ?? true,
      watermarkPosition:
          json['watermark_position'] as String? ?? 'bottom_right',
      watermarkAlpha: (json['watermark_alpha'] as num?)?.toDouble() ?? 0.55,
      subtitlesEnabled: json['subtitles_enabled'] as bool? ?? false,
      channelName: json['channel_name'] as String? ?? '',
      textRandomPosition: json['text_random_position'] as bool? ?? true,
      flipMode: json['flip_mode'] as String? ?? 'none',
      outputResolution: json['output_resolution'] as String? ?? '1080x1920',
      processingMode: json['processing_mode'] as String? ?? 'split_only',
    );
  }

  ProjectSettings copyWith({
    String? category,
    int? segmentSeconds,
    bool? watermarkEnabled,
    String? watermarkPosition,
    double? watermarkAlpha,
    bool? subtitlesEnabled,
    String? channelName,
    bool? textRandomPosition,
    String? flipMode,
    String? outputResolution,
    String? processingMode,
  }) {
    return ProjectSettings(
      category: category ?? this.category,
      segmentSeconds: segmentSeconds ?? this.segmentSeconds,
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
      watermarkAlpha: watermarkAlpha ?? this.watermarkAlpha,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      channelName: channelName ?? this.channelName,
      textRandomPosition: textRandomPosition ?? this.textRandomPosition,
      flipMode: flipMode ?? this.flipMode,
      outputResolution: outputResolution ?? this.outputResolution,
      processingMode: processingMode ?? this.processingMode,
    );
  }
}

class VideoProject {
  final String id;
  final String userId;
  final String title;
  final String sourceFilename;
  final double? sourceDurationSec;
  final String? sourceResolution;
  final ProjectSettings settings;
  final ProjectStatus status;
  final int? totalChunks;
  final int completedChunks;
  final int version; // Track re-renders
  final DateTime createdAt;
  final DateTime updatedAt;

  // Local-only fields (not stored in backend)
  String? localSourcePath;
  String? localOutputDir;

  VideoProject({
    required this.id,
    required this.userId,
    required this.title,
    required this.sourceFilename,
    this.sourceDurationSec,
    this.sourceResolution,
    required this.settings,
    required this.status,
    this.totalChunks,
    this.completedChunks = 0,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
    this.localSourcePath,
    this.localOutputDir,
  });

  // Convert to Map for Supabase
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'source_filename': sourceFilename,
      'source_duration_sec': sourceDurationSec,
      'source_resolution': sourceResolution,
      'settings': settings.toJson(),
      'status': status.name,
      'total_chunks': totalChunks,
      'completed_chunks': completedChunks,
      'version': version,
    };
  }

  // Create from Supabase Map
  factory VideoProject.fromSupabaseMap(Map<String, dynamic> map) {
    return VideoProject(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      sourceFilename: map['source_filename'] as String,
      sourceDurationSec: (map['source_duration_sec'] as num?)?.toDouble(),
      sourceResolution: map['source_resolution'] as String?,
      settings: ProjectSettings.fromJson(map['settings'] is String
          ? jsonDecode(map['settings'])
          : map['settings'] as Map<String, dynamic>),
      status: ProjectStatus.fromString(map['status'] as String),
      totalChunks: map['total_chunks'] as int?,
      completedChunks: map['completed_chunks'] as int? ?? 0,
      version: map['version'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Progress percentage (0.0 to 1.0)
  double get progressPercentage {
    if (totalChunks == null || totalChunks == 0) return 0.0;
    return completedChunks / totalChunks!;
  }

  // Copy with method
  VideoProject copyWith({
    ProjectStatus? status,
    int? totalChunks,
    int? completedChunks,
    int? version,
    String? localSourcePath,
    String? localOutputDir,
  }) {
    return VideoProject(
      id: id,
      userId: userId,
      title: title,
      sourceFilename: sourceFilename,
      sourceDurationSec: sourceDurationSec,
      sourceResolution: sourceResolution,
      settings: settings,
      status: status ?? this.status,
      totalChunks: totalChunks ?? this.totalChunks,
      completedChunks: completedChunks ?? this.completedChunks,
      version: version ?? this.version,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      localSourcePath: localSourcePath ?? this.localSourcePath,
      localOutputDir: localOutputDir ?? this.localOutputDir,
    );
  }

  @override
  String toString() {
    return 'VideoProject(id: $id, title: $title, status: $status, progress: ${(progressPercentage * 100).toStringAsFixed(1)}%)';
  }
}
