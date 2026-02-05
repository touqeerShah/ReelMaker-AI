import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/project_sync_service.dart';
import '../widgets/widgets.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _syncService = ProjectSyncService();
  bool _isLoading = true;
  String? _error;
  int _visibleProjects = 20;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _syncService.stopProjectPolling();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _visibleProjects = 20;
    });

    try {
      // Start polling for updates
      await _syncService.startProjectPolling();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('MMM d');

    return Scaffold(
      appBar: const CfAppBar(title: Text('Projects')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _syncService.projectsStream,
        builder: (context, snapshot) {
          // Show loading on initial load
          if (_isLoading && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show error if failed to load
          if (_error != null && !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: cs.error),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load projects',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadProjects,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Convert backend data to UI models
          final backendProjects = snapshot.data ?? [];
          final projects = backendProjects
              .map((json) => Project.fromBackendMap(json))
              .toList();

          // Show empty state if no projects
          if (projects.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_library_outlined,
                      size: 64, color: cs.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No projects yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a project to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            );
          }

          // Show project list
          return RefreshIndicator(
            onRefresh: () async {
              await _syncService.fetchProjectsOnce();
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemBuilder: (context, index) {
                final visibleCount = projects.length > _visibleProjects
                    ? _visibleProjects
                    : projects.length;
                if (index >= visibleCount) {
                  return Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _visibleProjects += 20;
                        });
                      },
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                          'Load more (${projects.length - visibleCount} left)'),
                    ),
                  );
                }
                final p = projects[index];
                final raw = backendProjects[index];
                final statusColor = projectStatusColor(p.status, cs);
                final sourceTitle =
                    raw['video_title']?.toString() ?? 'Source video';
                final thumbUrl =
                    raw['thumbnail_path']?.toString() ?? p.thumbnail;

                return CfCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => ProjectDetailScreen(project: p)),
                  ),
                  child: Row(
                    children: [
                      CfThumbnail(
                          url: thumbUrl,
                          width: 104,
                          height: 72,
                          overlayIcon: const Icon(Icons.play_arrow,
                              color: Colors.white)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              sourceTitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: cs.onSurface.withOpacity(0.65)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.schedule,
                                    size: 14,
                                    color: cs.onSurface.withOpacity(0.55)),
                                const SizedBox(width: 6),
                                Text(
                                  '${p.duration.inMinutes}m • ${df.format(p.createdAt)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color:
                                              cs.onSurface.withOpacity(0.55)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                CfStatusChip(
                                    label: projectStatusLabel(p.status),
                                    color: statusColor),
                                if (p.shortsCount > 0)
                                  CfPill(label: '${p.shortsCount} shorts'),
                                CfPill(label: p.languages.join(' / ')),
                              ],
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right,
                          color: cs.onSurface.withOpacity(0.5)),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: (projects.length > _visibleProjects
                      ? _visibleProjects
                      : projects.length) +
                  (projects.length > _visibleProjects ? 1 : 0),
            ),
          );
        },
      ),
    );
  }
}
