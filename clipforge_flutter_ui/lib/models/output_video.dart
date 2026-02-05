import 'dart:convert';

/// Represents a generated/split output video from a project
class OutputVideo {
  final String id;
  final String projectId;
  final String jobId;
  final int chunkIndex;
  final String filename;
  final String? filePath;
  final double? durationSec;
  final int? sizeBytes;
  final DateTime createdAt;

  OutputVideo({
    required this.id,
    required this.projectId,
    required this.jobId,
    required this.chunkIndex,
    required this.filename,
    this.filePath,
    this.durationSec,
    this.sizeBytes,
    required this.createdAt,
  });

  /// Generate standardized filename for output video
  /// Pattern: {originalBaseName}_001.mp4, _002.mp4, etc.
  static String generateFilename(String originalFilename, int chunkIndex) {
    // Extract base name without extension
    final lastDot = originalFilename.lastIndexOf('.');
    final baseName = lastDot > 0 
        ? originalFilename.substring(0, lastDot) 
        : originalFilename;
    final extension = lastDot > 0 
        ? originalFilename.substring(lastDot) 
        : '.mp4';
    
    // Format chunk index with leading zeros (001, 002, etc.)
    final paddedIndex = (chunkIndex + 1).toString().padLeft(3, '0');
    
    return '${baseName}_$paddedIndex$extension';
  }

  /// Convert to Map for backend API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'jobId': jobId,
      'chunkIndex': chunkIndex,
      'filename': filename,
      'filePath': filePath,
      'durationSec': durationSec,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from backend API response
  factory OutputVideo.fromJson(Map<String, dynamic> json) {
    return OutputVideo(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      jobId: json['job_id'] as String,
      chunkIndex: json['chunk_index'] as int,
      filename: json['filename'] as String,
      filePath: json['file_path'] as String?,
      durationSec: (json['duration_sec'] as num?)?.toDouble(),
      sizeBytes: json['size_bytes'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Create from local database Map
  factory OutputVideo.fromLocalMap(Map<String, dynamic> map) {
    return OutputVideo(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      jobId: map['job_id'] as String,
      chunkIndex: map['chunk_index'] as int,
      filename: map['filename'] as String,
      filePath: map['file_path'] as String?,
      durationSec: (map['duration_sec'] as num?)?.toDouble(),
      sizeBytes: map['size_bytes'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Convert to Map for local database
  Map<String, dynamic> toLocalMap() {
    return {
      'id': id,
      'project_id': projectId,
      'job_id': jobId,
      'chunk_index': chunkIndex,
      'filename': filename,
      'file_path': filePath,
      'duration_sec': durationSec,
      'size_bytes': sizeBytes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Copy with method for updating fields
  OutputVideo copyWith({
    String? filePath,
    double? durationSec,
    int? sizeBytes,
  }) {
    return OutputVideo(
      id: id,
      projectId: projectId,
      jobId: jobId,
      chunkIndex: chunkIndex,
      filename: filename,
      filePath: filePath ?? this.filePath,
      durationSec: durationSec ?? this.durationSec,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt,
    );
  }

  /// Format file size for display
  String get formattedSize {
    if (sizeBytes == null) return 'Unknown size';
    
    final bytes = sizeBytes!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  String toString() {
    return 'OutputVideo(id: $id, filename: $filename, chunk: $chunkIndex)';
  }
}
