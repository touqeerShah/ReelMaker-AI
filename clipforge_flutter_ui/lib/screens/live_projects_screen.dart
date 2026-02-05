import 'package:flutter/material.dart';
import 'dart:async';
import '../services/local_backend_api.dart';
import '../services/websocket_service.dart';
import '../widgets/project_progress_card.dart';
import '../widgets/queue_stats_widget.dart';

/// Screen showing real-time projects and queue status
/// Integrates with backend API and WebSocket for live updates
class LiveProjectsScreen extends StatefulWidget {
  const LiveProjectsScreen({Key? key}) : super(key: key);

  @override
  State<LiveProjectsScreen> createState() => _LiveProjectsScreenState();
}

class _LiveProjectsScreenState extends State<LiveProjectsScreen> {
  final _api = LocalBackendAPI();
  final _ws = WebSocketService();
  
  List<Map<String, dynamic>> _projects = [];
  Map<String, dynamic>? _queueStats;
  bool _isLoading = true;
  String? _error;
  
  StreamSubscription? _projectCreatedSub;
  StreamSubscription? _projectUpdatedSub;
  StreamSubscription? _jobUpdatedSub;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _projectCreatedSub?.cancel();
    _projectUpdatedSub?.cancel();
    _jobUpdatedSub?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Connect WebSocket if authenticated
    if (_api.isAuthenticated && _api.token != null) {
      await _ws.connect(_api.baseUrl, _api.token!);
      
      // Listen to real-time updates
      _projectCreatedSub = _ws.projectCreatedStream.listen((data) {
        print('📦 Project created: $data');
        _loadProjects(); // Reload projects
      });
      
      _projectUpdatedSub = _ws.projectUpdatedStream.listen((data) {
        print('📦 Project updated: $data');
        _loadProjects(); // Reload projects
      });
      
      _jobUpdatedSub = _ws.jobUpdatedStream.listen((data) {
        print('⚙️ Job updated: $data');
        // Update project progress if job belongs to a visible project
        _loadProjects();
      });
    }
    
    // Load initial data
    await _loadProjects();
    await _loadQueueStats();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await _api.getProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadQueueStats() async {
    try {
      final stats = await _api.getQueueStats();
      if (mounted) {
        setState(() {
          _queueStats = stats;
        });
      }
    } catch (e) {
      print('Error loading queue stats: $e');
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadProjects(),
      _loadQueueStats(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects & Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Queue Statistics Header
        if (_queueStats != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: QueueStatsWidget(
                totalJobs: _queueStats!['total_jobs'] ?? 0,
                pendingJobs: _queueStats!['pending_jobs'] ?? 0,
                runningJobs: _queueStats!['running_jobs'] ?? 0,
                completedJobs: _queueStats!['completed_jobs'] ?? 0,
                failedJobs: _queueStats!['failed_jobs'] ?? 0,
              ),
            ),
          ),
        
        // Section Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Text(
                  'Your Projects',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_projects.length} total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Projects List
        if (_projects.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No projects yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload a video to get started',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.separated(
              itemCount: _projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildProjectCard(_projects[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    return FutureBuilder<Map<String, dynamic>>(
      // Fetch detailed stats for each project
      future: _api.getProjectStats(project['id']),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? project;
        
        return ProjectProgressCard(
          title: project['title'] ?? 'Untitled Project',
          status: project['status'] ?? 'pending',
          totalChunks: stats['total_chunks'] ?? project['total_chunks'] ?? 0,
          completedChunks: stats['completed_chunks'] ?? project['completed_chunks'] ?? 0,
          failedChunks: stats['failed_chunks'] ?? 0,
          progress: (project['progress'] ?? 0.0).toDouble(),
          queuePosition: stats['queue_position'],
          onTap: () => _navigateToProjectDetails(project),
        );
      },
    );
  }

  void _navigateToProjectDetails(Map<String, dynamic> project) {
    // Navigate to project detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailsView(
          projectId: project['id'],
        ),
      ),
    );
  }
}

/// Simple project details view
class ProjectDetailsView extends StatelessWidget {
  final String projectId;

  const ProjectDetailsView({Key? key, required this.projectId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final api = LocalBackendAPI();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Details'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: api.getProjectStats(projectId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          final stats = snapshot.data!;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoRow('Status', stats['status']),
              _buildInfoRow('Total Chunks', '${stats['total_chunks']}'),
              _buildInfoRow('Completed', '${stats['completed_chunks']}'),
              _buildInfoRow('Failed', '${stats['failed_chunks']}'),
              _buildInfoRow('Remaining', '${stats['remaining_chunks']}'),
              _buildInfoRow('Progress', '${(stats['progress'] * 100).toStringAsFixed(1)}%'),
              if (stats['queue_position'] != null)
                _buildInfoRow('Queue Position', '#${stats['queue_position']}'),
              if (stats['estimated_time_remaining'] != null)
                _buildInfoRow('Est. Time', stats['estimated_time_remaining']),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
