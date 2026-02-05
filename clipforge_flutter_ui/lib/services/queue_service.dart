import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/video_project.dart';
import '../models/processing_job.dart';

/// Service to fetch and stream video processing queue data from Supabase
class QueueService {
  final _supabase = Supabase.instance.client;

  /// Fetch all projects for the current user
  Future<List<VideoProject>> fetchProjects() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _supabase
        .from('projects')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => VideoProject.fromSupabaseMap(json))
        .toList();
  }

  /// Fetch jobs for a specific project
  Future<List<ProcessingJob>> fetchJobsForProject(String projectId) async {
    final response = await _supabase
        .from('processing_jobs')
        .select()
        .eq('project_id', projectId)
        .order('chunk_index', ascending: true);

    return (response as List)
        .map((json) => ProcessingJob.fromSupabaseMap(json))
        .toList();
  }

  /// Stream project updates in real-time
  Stream<List<VideoProject>> streamProjects() async* {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      yield [];
      return;
    }

    // Initial fetch
    yield await fetchProjects();

    // Listen for realtime updates
    await for (final _ in _supabase
        .from('projects')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)) {
      yield await fetchProjects();
    }
  }

  /// Stream jobs for a specific project
  Stream<List<ProcessingJob>> streamJobsForProject(String projectId) async* {
    // Initial fetch
    yield await fetchJobsForProject(projectId);

    // Listen for realtime updates
    await for (final _ in _supabase
        .from('processing_jobs')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)) {
      yield await fetchJobsForProject(projectId);
    }
  }

  /// Get project progress summary
  Future<Map<String, dynamic>> getProjectProgress(String projectId) async {
    final response = await _supabase
        .from('project_progress')
        .select()
        .eq('id', projectId)
        .single();

    return response;
  }

  /// Delete a project and all its jobs
  Future<void> deleteProject(String projectId) async {
    await _supabase
        .from('projects')
        .delete()
        .eq('id', projectId);
    // Jobs will be cascade deleted by database
  }

  /// Retry a failed job
  Future<void> retryJob(String jobId) async {
    await _supabase
        .from('processing_jobs')
        .update({
          'status': 'pending',
          'error_message': null,
          'progress': 0.0,
          'processing_started_at': null,
          'processing_completed_at': null,
        })
        .eq('id', jobId);
  }
}
