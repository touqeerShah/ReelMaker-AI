/// Progress information for video export
class ExportProgress {
  /// Current segment being processed (0-indexed)
  final int currentSegment;
  
  /// Total number of segments
  final int totalSegments;
  
  /// Progress percentage (0.0 - 1.0)
  final double progress;
  
  /// Current status message
  final String status;
  
  /// Output file path (if completed)
  final String? outputPath;
  
  /// Error message (if failed)
  final String? error;

  const ExportProgress({
    required this.currentSegment,
    required this.totalSegments,
    required this.progress,
    required this.status,
    this.outputPath,
    this.error,
  });

  factory ExportProgress.fromMap(Map<dynamic, dynamic> map) {
    return ExportProgress(
      currentSegment: map['currentSegment'] as int? ?? 0,
      totalSegments: map['totalSegments'] as int? ?? 1,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? '',
      outputPath: map['outputPath'] as String?,
      error: map['error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'currentSegment': currentSegment,
      'totalSegments': totalSegments,
      'progress': progress,
      'status': status,
      if (outputPath != null) 'outputPath': outputPath,
      if (error != null) 'error': error,
    };
  }

  bool get isCompleted => progress >= 1.0 && outputPath != null;
  bool get hasFailed => error != null;

  @override
  String toString() {
    return 'ExportProgress(segment: $currentSegment/$totalSegments, progress: ${(progress * 100).toStringAsFixed(1)}%, status: $status)';
  }
}
