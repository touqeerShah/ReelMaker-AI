enum JobStatus {
  pending,
  running,
  completed,
  failed;

  static JobStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return JobStatus.pending;
      case 'running':
        return JobStatus.running;
      case 'completed':
        return JobStatus.completed;
      case 'failed':
        return JobStatus.failed;
      default:
        return JobStatus.pending;
    }
  }

  String toJson() => name;
}

class ProcessingJob {
  final String id;
  final String projectId;
  final int chunkIndex;
  final double startSec;
  final double durationSec;
  final JobStatus status;
  final double progress;
  final String? outputFilename;
  final String? errorMessage;
  final DateTime? processingStartedAt;
  final DateTime? processingCompletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProcessingJob({
    required this.id,
    required this.projectId,
    required this.chunkIndex,
    required this.startSec,
    required this.durationSec,
    required this.status,
    this.progress = 0.0,
    this.outputFilename,
    this.errorMessage,
    this.processingStartedAt,
    this.processingCompletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to Map for local database storage
  Map<String, dynamic> toLocalMap() {
    return {
      'id': id,
      'project_id': projectId,
      'chunk_index': chunkIndex,
      'start_sec': startSec,
      'duration_sec': durationSec,
      'status': status.name,
      'progress': progress,
      'output_filename': outputFilename,
      'error_message': errorMessage,
      'processing_started_at': processingStartedAt?.toIso8601String(),
      'processing_completed_at': processingCompletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Convert to Map for Supabase
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'project_id': projectId,
      'chunk_index': chunkIndex,
      'start_sec': startSec,
      'duration_sec': durationSec,
      'status': status.name,
      'progress': progress,
      'output_filename': outputFilename,
      'error_message': errorMessage,
      'processing_started_at': processingStartedAt?.toIso8601String(),
      'processing_completed_at': processingCompletedAt?.toIso8601String(),
    };
  }

  // Create from local database Map
  factory ProcessingJob.fromLocalMap(Map<String, dynamic> map) {
    return ProcessingJob(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      chunkIndex: (map['chunk_index'] as num?)?.toInt() ?? 0,
      startSec: (map['start_sec'] as num?)?.toDouble() ?? 0.0,
      durationSec: (map['duration_sec'] as num?)?.toDouble() ?? 0.0,
      status: JobStatus.fromString(map['status'] as String),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      outputFilename: map['output_filename'] as String?,
      errorMessage: map['error_message'] as String?,
      processingStartedAt: map['processing_started_at'] != null
          ? DateTime.parse(map['processing_started_at'] as String)
          : null,
      processingCompletedAt: map['processing_completed_at'] != null
          ? DateTime.parse(map['processing_completed_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Create from Supabase Map
  factory ProcessingJob.fromSupabaseMap(Map<String, dynamic> map) {
    return ProcessingJob(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      chunkIndex: map['chunk_index'] as int,
      startSec: (map['start_sec'] as num).toDouble(),
      durationSec: (map['duration_sec'] as num).toDouble(),
      status: JobStatus.fromString(map['status'] as String),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      outputFilename: map['output_filename'] as String?,
      errorMessage: map['error_message'] as String?,
      processingStartedAt: map['processing_started_at'] != null
          ? DateTime.parse(map['processing_started_at'] as String)
          : null,
      processingCompletedAt: map['processing_completed_at'] != null
          ? DateTime.parse(map['processing_completed_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Copy with method for updating fields
  ProcessingJob copyWith({
    JobStatus? status,
    double? progress,
    String? outputFilename,
    String? errorMessage,
    DateTime? processingStartedAt,
    DateTime? processingCompletedAt,
  }) {
    return ProcessingJob(
      id: id,
      projectId: projectId,
      chunkIndex: chunkIndex,
      startSec: startSec,
      durationSec: durationSec,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputFilename: outputFilename ?? this.outputFilename,
      errorMessage: errorMessage ?? this.errorMessage,
      processingStartedAt: processingStartedAt ?? this.processingStartedAt,
      processingCompletedAt:
          processingCompletedAt ?? this.processingCompletedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ProcessingJob(id: $id, chunk: $chunkIndex, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}
