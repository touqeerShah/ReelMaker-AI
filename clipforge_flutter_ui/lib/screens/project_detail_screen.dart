import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/local_backend_api.dart';
import '../services/local_queue_db.dart';
import '../services/project_sync_service.dart';
import '../widgets/widgets.dart';
import 'queue_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final _api = LocalBackendAPI();
  final _syncService = ProjectSyncService();
  StreamSubscription<List<Map<String, dynamic>>>? _jobsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _projectsSub;
  String? _jobsFingerprint;
  int _lastCompletedCount = -1;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _projectData;
  List<dynamic> _outputs = const [];
  List<dynamic> _jobs = const [];
  bool _loadingCandidates = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startLiveUpdates();
  }

  void _startLiveUpdates() {
    _syncService.startJobPolling();
    _syncService.startProjectPolling();

    _jobsSub = _syncService.jobsStream.listen((jobs) async {
      final filtered = jobs
          .where(
              (j) => (j['project_id']?.toString() ?? '') == widget.project.id)
          .toList();

      final fingerprint = filtered
          .map((j) =>
              '${j['id']}:${j['status']}:${j['progress']}:${j['error_message']}')
          .join('|');
      if (fingerprint == _jobsFingerprint) return;
      _jobsFingerprint = fingerprint;

      if (!mounted) return;
      setState(() => _jobs = filtered);

      final completedCount = filtered
          .where((j) => (j['status']?.toString() ?? '') == 'completed')
          .length;
      if (completedCount != _lastCompletedCount) {
        _lastCompletedCount = completedCount;
        try {
          final outputs = await _api.getProjectOutputs(widget.project.id);
          if (mounted) {
            setState(() => _outputs = outputs);
          }
        } catch (_) {}
      }
    });

    _projectsSub = _syncService.projectsStream.listen((projects) {
      final match = projects.cast<Map<String, dynamic>>().firstWhere(
            (p) => (p['id']?.toString() ?? '') == widget.project.id,
            orElse: () => const <String, dynamic>{},
          );
      if (match.isEmpty || !mounted) return;
      setState(() {
        _projectData = {
          ...(_projectData ?? const <String, dynamic>{}),
          ...match,
        };
      });
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _api.getProject(widget.project.id),
        _api.getProjectOutputs(widget.project.id),
        _api.getJobs(projectId: widget.project.id),
      ]);

      if (!mounted) return;
      setState(() {
        _projectData = results[0] as Map<String, dynamic>;
        _outputs = results[1] as List<dynamic>;
        _jobs = results[2] as List<dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _settingsMap() {
    final raw = _projectData?['settings_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return {};
  }

  String _processingMode(Map<String, dynamic> settings) {
    return (settings['processing_mode']?.toString() ?? '').toLowerCase();
  }

  bool _isSummaryProject(Map<String, dynamic> settings) {
    final category = (settings['category']?.toString() ?? '').toLowerCase();
    final mode = _processingMode(settings);
    if (mode == 'ai_best_scenes_split') return false;
    return category == 'summary';
  }

  bool _usesAiSettings(Map<String, dynamic> settings) {
    final mode = _processingMode(settings);
    return mode.startsWith('ai_');
  }

  String _formatTimestamp(double seconds) {
    final total = seconds.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openSummarySelection(String jobId) async {
    if (_loadingCandidates) return;
    setState(() => _loadingCandidates = true);
    try {
      final data = await _api.getSummaryCandidates(widget.project.id);
      if (!mounted) return;

      final candidatesRaw = (data['candidates'] as List?) ?? const [];
      final suggestedRaw = (data['suggested'] as List?) ?? const [];

      final candidates = candidatesRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final suggested = suggestedRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No candidates available yet.')),
        );
        return;
      }

      String keyFor(Map<String, dynamic> s) =>
          '${s['chunkIndex']}_${s['startSec']}_${s['endSec']}';

      final selectedKeys = <String>{
        for (final s in (suggested.isNotEmpty ? suggested : candidates))
          keyFor(s),
      };

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Select Summary Scenes',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedKeys
                                  ..clear()
                                  ..addAll(candidates.map(keyFor));
                              });
                            },
                            child: const Text('Select all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: candidates.length,
                          itemBuilder: (ctx, idx) {
                            final s = candidates[idx];
                            final start = (s['startSec'] as num?)?.toDouble() ?? 0;
                            final end = (s['endSec'] as num?)?.toDouble() ?? 0;
                            final chunkIndex = (s['chunkIndex'] as num?)?.toInt() ?? 0;
                            final story = (s['storyText']?.toString() ?? '').trim();
                            final k = keyFor(s);
                            return CheckboxListTile(
                              value: selectedKeys.contains(k),
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    selectedKeys.add(k);
                                  } else {
                                    selectedKeys.remove(k);
                                  }
                                });
                              },
                              title: Text(
                                'Chunk ${chunkIndex + 1} • ${_formatTimestamp(start)} - ${_formatTimestamp(end)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: story.isNotEmpty ? Text(story) : const Text('No narration text'),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final selected = candidates
                                    .where((s) => selectedKeys.contains(keyFor(s)))
                                    .toList();
                                if (selected.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Select at least one scene.')),
                                  );
                                  return;
                                }
                                await _api.submitSummarySelection(
                                  projectId: widget.project.id,
                                  jobId: jobId,
                                  selected: selected,
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Selection submitted. Rendering started.')),
                                );
                              },
                              child: const Text('Generate'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load candidates: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingCandidates = false);
      }
    }
  }

  Future<void> _showReRenderDialog() async {
    final settings = _settingsMap();
    final isSummary = _isSummaryProject(settings);
    final isAiMode = _usesAiSettings(settings);
    final segmentController = TextEditingController(
      text: '${settings['segment_seconds'] ?? 60}',
    );
    final subscribeController = TextEditingController(
      text: '${settings['subscribe_seconds'] ?? 5}',
    );
    final aiMap = (settings['ai_best_scenes'] is Map)
        ? Map<String, dynamic>.from(settings['ai_best_scenes'] as Map)
        : <String, dynamic>{};
    final chunkController = TextEditingController(
      text: '${aiMap['srt_chunk_size'] ?? 220}',
    );
    final minSceneController = TextEditingController(
      text: '${aiMap['min_scene_sec'] ?? 20}',
    );
    final maxSceneController = TextEditingController(
      text: '${aiMap['max_scene_sec'] ?? 55}',
    );
    final thresholdController = TextEditingController(
      text: '${aiMap['score_threshold'] ?? 72}',
    );
    final gapController = TextEditingController(
      text: '${aiMap['min_gap_sec'] ?? 2.0}',
    );
    final perChunkController = TextEditingController(
      text: '${aiMap['segments_per_chunk'] ?? 1}',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-render Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isAiMode) ...[
              TextField(
                controller: segmentController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Split length (seconds)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subscribeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Subscribe overlay (seconds)'),
              ),
            ] else ...[
              TextField(
                controller: chunkController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SRT chunk size'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: minSceneController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Min scene seconds'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: maxSceneController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Max scene seconds'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: thresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Score threshold'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: gapController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min gap seconds'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: perChunkController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Segments per chunk'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Re-render'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final updatedSettings = {...settings};
      if (!isAiMode) {
        final segmentSeconds =
            int.tryParse(segmentController.text.trim()) ?? 60;
        final subscribeSeconds =
            int.tryParse(subscribeController.text.trim()) ?? 5;
        updatedSettings['segment_seconds'] = segmentSeconds;
        updatedSettings['subscribe_seconds'] = subscribeSeconds;
      } else {
        if (isSummary) {
          updatedSettings['category'] = 'summary';
          updatedSettings['summary_type'] = 'best_scenes';
        }
        updatedSettings['ai_best_scenes'] = {
          ...aiMap,
          'srt_chunk_size': int.tryParse(chunkController.text.trim()) ?? 220,
          'min_scene_sec':
              double.tryParse(minSceneController.text.trim()) ?? 20,
          'max_scene_sec':
              double.tryParse(maxSceneController.text.trim()) ?? 55,
          'score_threshold':
              int.tryParse(thresholdController.text.trim()) ?? 72,
          'min_gap_sec': double.tryParse(gapController.text.trim()) ?? 2.0,
          'segments_per_chunk':
              int.tryParse(perChunkController.text.trim()) ?? 1,
        };
      }

      await _api.reRenderProject(
        projectId: widget.project.id,
        settings: updatedSettings,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(isAiMode
                ? 'Re-render queued with updated AI best-scene settings'
                : 'Re-render queued with new split settings')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Re-render failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteOutput(String outputId) async {
    try {
      await _api.deleteOutput(outputId);
      if (!mounted) return;
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to delete output: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteProject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: const Text(
          'This removes generated split videos for this project. The original source video is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteProject(widget.project.id);
      await LocalQueueDb().deleteJobsForProject(widget.project.id);
      await LocalQueueDb().deleteCachedProject(widget.project.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Project deleted (original video preserved)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to delete project: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _projectData?['title']?.toString() ?? widget.project.title;
    final status = _projectData?['status']?.toString() ??
        projectStatusLabel(widget.project.status);
    final sourceFilename = _projectData?['filename']?.toString() ??
        _projectData?['video_title']?.toString() ??
        title;
    final settings = _settingsMap();
    final isSummary = _isSummaryProject(settings);
    final mode = _processingMode(settings);
    final categoryLabel = mode == 'ai_best_scenes_split'
        ? 'Split • Best Scenes (Clips)'
        : isSummary
            ? 'Summary • Best Scenes'
            : 'Split';
    final runningJobs =
        _jobs.where((j) => (j['status']?.toString() ?? '') == 'running').length;
    final pendingJobs = _jobs.where((j) {
      final s = (j['status']?.toString() ?? '').toLowerCase();
      return s == 'pending' || s == 'awaiting_selection';
    }).length;

    return Scaffold(
      appBar: CfAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Failed to load project details\n$_error',
                      textAlign: TextAlign.center))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    CfCard(
                      padding: const EdgeInsets.all(12),
                      child: ListTile(
                        leading: Icon(
                            isSummary ? Icons.auto_awesome : Icons.video_file),
                        title: Text('Original Video • $categoryLabel'),
                        subtitle: Text(sourceFilename),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Queue for this Project',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        CfPill(label: '$runningJobs running'),
                        const SizedBox(width: 8),
                        CfPill(label: '$pendingJobs pending'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_jobs.isEmpty)
                      CfCard(
                        padding: const EdgeInsets.all(16),
                        child:
                            const Text('No queue jobs yet for this project.'),
                      )
                    else
                      ..._jobs.map((job) {
                        final chunk = (job['chunk_index'] ??
                            job['chunkIndex'] ??
                            0) as int;
                        final statusRaw =
                            (job['status']?.toString() ?? 'pending')
                                .toLowerCase();
                        final status = statusRaw.toUpperCase();
                        final progress =
                            ((job['progress'] as num?)?.toDouble() ?? 0) * 100;
                        final step =
                            (job['error_message']?.toString() ?? '').trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CfCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.queue_play_next),
                              title: Text('Chunk ${chunk + 1}'),
                              subtitle: Text(step.isNotEmpty
                                  ? '$status • ${progress.toStringAsFixed(0)}% • $step'
                                  : '$status • ${progress.toStringAsFixed(0)}%'),
                              trailing: statusRaw == 'awaiting_selection'
                                  ? OutlinedButton(
                                      onPressed: _loadingCandidates
                                          ? null
                                          : () => _openSummarySelection(
                                              job['id']?.toString() ?? ''),
                                      child: const Text('Select Scenes'),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => QueueScreen(
                                      initialFilter: QueueFilter.running,
                                      projectId: widget.project.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                            mode == 'ai_best_scenes_split'
                                ? 'Best Scene Clips'
                                : isSummary
                                    ? 'Best Scene Results'
                                    : 'Split Video Results',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        CfPill(label: '${_outputs.length} clips'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_outputs.isEmpty)
                      CfCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No clips yet. Processing is still running.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else
                      ..._outputs.map((output) {
                        final id = output['id']?.toString() ?? '';
                        final name =
                            output['filename']?.toString() ?? 'clip.mp4';
                        final idx = (output['chunk_index'] as int?) ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CfCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.movie_outlined),
                              title: Text(name),
                              subtitle: Text('Part ${idx + 1}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete output',
                                onPressed: () => _deleteOutput(id),
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    CfCard(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.replay),
                            title: const Text('Re-render'),
                            subtitle: Text(isSummary
                                ? 'Change AI best-scene settings'
                                : 'Change split and subscribe overlay settings'),
                            onTap: _showReRenderDialog,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.delete_forever_outlined),
                            title: const Text('Delete project'),
                            subtitle: const Text(
                                'Deletes generated clips only, keeps original video'),
                            onTap: _deleteProject,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
    _projectsSub?.cancel();
    super.dispose();
  }
}
