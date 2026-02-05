import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/processing_job.dart';

/// Local SQLite database for managing job queue and caching project data
/// This runs entirely on-device - no cloud database dependency
class LocalQueueDb {
  static LocalQueueDb? _instance;
  static Database? _database;

  LocalQueueDb._();

  factory LocalQueueDb() {
    _instance ??= LocalQueueDb._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'clipforge_queue.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Processing jobs table
    await db.execute('''
      CREATE TABLE processing_jobs (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        start_sec REAL NOT NULL,
        duration_sec REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        progress REAL DEFAULT 0,
        output_filename TEXT,
        error_message TEXT,
        processing_started_at TEXT,
        processing_completed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(project_id, chunk_index)
      )
    ''');

    // Index for efficient queue queries
    await db.execute('''
      CREATE INDEX idx_jobs_project_id ON processing_jobs(project_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_jobs_status ON processing_jobs(status)
    ''');

    // Project cache table (optional - stores minimal project info locally)
    await db.execute('''
      CREATE TABLE project_cache (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source_filename TEXT NOT NULL,
        local_source_path TEXT,
        local_output_dir TEXT,
        settings_json TEXT NOT NULL,
        status TEXT NOT NULL,
        total_chunks INTEGER,
        completed_chunks INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations here
  }

  // ============================================================
  // JOB OPERATIONS
  // ============================================================

  /// Insert a new job into the queue
  Future<void> insertJob(ProcessingJob job) async {
    final db = await database;
    await db.insert(
      'processing_jobs',
      job.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple jobs (batch operation)
  Future<void> insertJobs(List<ProcessingJob> jobs) async {
    final db = await database;
    final batch = db.batch();
    
    for (final job in jobs) {
      batch.insert(
        'processing_jobs',
        job.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  /// Get the next pending job (FIFO order by chunk_index)
  Future<ProcessingJob?> getNextPendingJob() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'processing_jobs',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'chunk_index ASC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ProcessingJob.fromLocalMap(maps.first);
  }

  /// Get all jobs for a specific project
  Future<List<ProcessingJob>> getJobsForProject(String projectId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'processing_jobs',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'chunk_index ASC',
    );

    return maps.map((map) => ProcessingJob.fromLocalMap(map)).toList();
  }

  /// Get a specific job by ID
  Future<ProcessingJob?> getJob(String jobId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'processing_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ProcessingJob.fromLocalMap(maps.first);
  }

  /// Update job status and progress
  Future<void> updateJobStatus(
    String jobId,
    JobStatus status, {
    double? progress,
    String? errorMessage,
    DateTime? processingStartedAt,
    DateTime? processingCompletedAt,
  }) async {
    final db = await database;
    
    final updateData = <String, dynamic>{
      'status': status.name,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (progress != null) updateData['progress'] = progress;
    if (errorMessage != null) updateData['error_message'] = errorMessage;
    if (processingStartedAt != null) {
      updateData['processing_started_at'] = processingStartedAt.toIso8601String();
    }
    if (processingCompletedAt != null) {
      updateData['processing_completed_at'] = processingCompletedAt.toIso8601String();
    }

    await db.update(
      'processing_jobs',
      updateData,
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  /// Mark job as completed with output filename
  Future<void> markJobAsCompleted(String jobId, String outputFilename) async {
    final db = await database;
    await db.update(
      'processing_jobs',
      {
        'status': 'completed',
        'output_filename': outputFilename,
        'processing_completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'progress': 1.0,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  /// Mark job as failed with error message
  Future<void> markJobAsFailed(String jobId, String errorMessage) async {
    final db = await database;
    await db.update(
      'processing_jobs',
      {
        'status': 'failed',
        'error_message': errorMessage,
        'processing_completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  /// Get count of jobs by status
  Future<Map<String, int>> getJobCountsByStatus() async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM processing_jobs 
      GROUP BY status
    ''');

    final counts = <String, int>{};
    for (final row in result) {
      counts[row['status'] as String] = row['count'] as int;
    }
    
    return counts;
  }

  /// Delete all jobs for a project
  Future<void> deleteJobsForProject(String projectId) async {
    final db = await database;
    await db.delete(
      'processing_jobs',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
  }

  /// Delete a specific job
  Future<void> deleteJob(String jobId) async {
    final db = await database;
    await db.delete(
      'processing_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  // ============================================================
  // PROJECT CACHE OPERATIONS (Optional - for offline capability)
  // ============================================================

  /// Cache project info locally
  Future<void> cacheProject({
    required String id,
    required String title,
    required String sourceFilename,
    String? localSourcePath,
    String? localOutputDir,
    required String settingsJson,
    required String status,
    int? totalChunks,
    int completedChunks = 0,
  }) async {
    final db = await database;
    await db.insert(
      'project_cache',
      {
        'id': id,
        'title': title,
        'source_filename': sourceFilename,
        'local_source_path': localSourcePath,
        'local_output_dir': localOutputDir,
        'settings_json': settingsJson,
        'status': status,
        'total_chunks': totalChunks,
        'completed_chunks': completedChunks,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get cached project
  Future<Map<String, dynamic>?> getCachedProject(String projectId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'project_cache',
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// Update project cache status
  Future<void> updateProjectCacheStatus(String projectId, String status) async {
    final db = await database;
    await db.update(
      'project_cache',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  /// Delete cached project
  Future<void> deleteCachedProject(String projectId) async {
    final db = await database;
    await db.delete(
      'project_cache',
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  // ============================================================
  // UTILITY OPERATIONS
  // ============================================================

  /// Clear all pending jobs (useful for debugging/reset)
  Future<void> clearPendingJobs() async {
    final db = await database;
    await db.delete(
      'processing_jobs',
      where: 'status = ?',
      whereArgs: ['pending'],
    );
  }

  /// Clear all data (nuclear option)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('processing_jobs');
    await db.delete('project_cache');
  }

  /// Close database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
