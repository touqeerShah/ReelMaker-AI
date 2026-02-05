import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_backend_api.dart';
import 'queue_sync_service.dart';

/// Service to synchronize project and job data from backend
/// Provides streams for real-time updates via periodic polling
class ProjectSyncService {
  static final ProjectSyncService _instance = ProjectSyncService._internal();
  factory ProjectSyncService() => _instance;
  ProjectSyncService._internal();

  final LocalBackendAPI _api = LocalBackendAPI();
  final QueueSyncService _queueSync = QueueSyncService();

  Timer? _projectsTimer;
  Timer? _jobsTimer;

  final _projectsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _jobsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  bool _isPollingProjects = false;
  bool _isPollingJobs = false;
  bool _wsHooksAttached = false;

  /// Stream of projects from backend
  Stream<List<Map<String, dynamic>>> get projectsStream =>
      _projectsController.stream;

  /// Stream of jobs from backend
  Stream<List<Map<String, dynamic>>> get jobsStream => _jobsController.stream;

  /// Start polling for project updates
  Future<void> startProjectPolling(
      {Duration interval = const Duration(seconds: 5)}) async {
    if (_isPollingProjects) return;

    print('[ProjectSyncService] Starting project polling...');
    _isPollingProjects = true;

    // Fetch immediately
    await _fetchProjects();

    // Then poll periodically
    _projectsTimer = Timer.periodic(interval, (_) async {
      await _fetchProjects();
    });
  }

  /// Start polling for job updates
  Future<void> startJobPolling(
      {Duration interval = const Duration(seconds: 3)}) async {
    if (_isPollingJobs) return;

    print('[ProjectSyncService] Starting job polling...');
    _isPollingJobs = true;

    // Fetch immediately
    await _fetchJobs();
    await _fetchProjects();
    _attachWebSocketHooksIfNeeded();

    // Then poll periodically
    _jobsTimer = Timer.periodic(interval, (_) async {
      await _fetchJobs();
    });
  }

  void _attachWebSocketHooksIfNeeded() {
    if (_wsHooksAttached) return;
    _wsHooksAttached = true;

    _queueSync.onJobUpdated = (data) async {
      final job = data['job'];
      if (job is Map<String, dynamic>) {
        debugPrint(
            '[ProjectSyncService] WS job update: id=${job['id']} status=${job['status']} progress=${job['progress']} step=${job['error_message']}');
      } else {
        debugPrint('[ProjectSyncService] WS job update: $data');
      }
      await _fetchJobs();
      await _fetchProjects();
    };

    _queueSync.onJobCompleted = (data) async {
      debugPrint('[ProjectSyncService] WS job completed: $data');
      await _fetchJobs();
      await _fetchProjects();
    };

    _queueSync.onJobFailed = (data) async {
      debugPrint('[ProjectSyncService] WS job failed: $data');
      await _fetchJobs();
      await _fetchProjects();
    };
  }

  /// Stop polling for projects
  void stopProjectPolling() {
    print('[ProjectSyncService] Stopping project polling...');
    _projectsTimer?.cancel();
    _projectsTimer = null;
    _isPollingProjects = false;
  }

  /// Stop polling for jobs
  void stopJobPolling() {
    print('[ProjectSyncService] Stopping job polling...');
    _jobsTimer?.cancel();
    _jobsTimer = null;
    _isPollingJobs = false;
  }

  /// Stop all polling
  void stopAll() {
    stopProjectPolling();
    stopJobPolling();
  }

  /// Fetch projects from backend
  Future<void> _fetchProjects() async {
    try {
      if (!_api.isAuthenticated) {
        print('[ProjectSyncService] Not authenticated, skipping project fetch');
        _projectsController.add([]);
        return;
      }

      final response = await _api.getProjects();
      final projects = response.map((e) => e as Map<String, dynamic>).toList();
      _projectsController.add(projects);
    } catch (e) {
      print('[ProjectSyncService] Error fetching projects: $e');
      // Don't emit error, just keep previous state
    }
  }

  /// Fetch jobs from backend
  Future<void> _fetchJobs() async {
    try {
      if (!_api.isAuthenticated) {
        print('[ProjectSyncService] Not authenticated, skipping job fetch');
        _jobsController.add([]);
        return;
      }

      final response = await _api.getJobs();
      final jobs = response.map((e) => e as Map<String, dynamic>).toList();
      _jobsController.add(jobs);
    } catch (e) {
      print('[ProjectSyncService] Error fetching jobs: $e');
      // Don't emit error, just keep previous state
    }
  }

  /// Fetch projects once (no polling)
  Future<List<Map<String, dynamic>>> fetchProjectsOnce() async {
    try {
      if (!_api.isAuthenticated) {
        return [];
      }
      final response = await _api.getProjects();
      return response.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('[ProjectSyncService] Error fetching projects: $e');
      return [];
    }
  }

  /// Fetch jobs once (no polling)
  Future<List<Map<String, dynamic>>> fetchJobsOnce() async {
    try {
      if (!_api.isAuthenticated) {
        return [];
      }
      final response = await _api.getJobs();
      return response.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('[ProjectSyncService] Error fetching jobs: $e');
      return [];
    }
  }

  /// Force refresh job stream immediately
  Future<void> refreshJobsNow() async {
    await _fetchJobs();
  }

  /// Dispose resources
  void dispose() {
    stopAll();
    _projectsController.close();
    _jobsController.close();
  }
}
