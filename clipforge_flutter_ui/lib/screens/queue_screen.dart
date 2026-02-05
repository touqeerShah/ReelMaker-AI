import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/processing_job.dart' as local_job;
import '../services/local_backend_api.dart';
import '../services/local_queue_db.dart';
import '../services/project_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'video_preview_screen.dart';

enum QueueFilter { all, running, completed, failed }

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    this.initialFilter,
    this.projectId,
  });

  final QueueFilter? initialFilter;
  final String? projectId;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  QueueFilter _filter = QueueFilter.running;
  final _syncService = ProjectSyncService();
  final _api = LocalBackendAPI();
  bool _isLoading = true;
  int _visibleJobs = 20;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? QueueFilter.running;
    _loadJobs();
  }

  @override
  void dispose() {
    _syncService.stopJobPolling();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Start polling for updates (every 3 seconds)
      await _syncService.startJobPolling(interval: const Duration(seconds: 3));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('[QueueScreen] Error loading jobs: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CfAppBar(
        title: const Text('Processing Queue'),
        actions: [
          TextButton(
            onPressed: () async {
              // Refresh jobs
              await _syncService.refreshJobsNow();
            },
            child: const Text('Refresh'),
          )
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _syncService.jobsStream,
        builder: (context, snapshot) {
          // Show loading on initial load
          if (_isLoading && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Convert backend data to UI models
          final backendJobs = snapshot.data ?? [];
          final jobs =
              backendJobs.map((json) => Job.fromBackendMap(json)).toList();

          // Apply filter
          final scopedJobs = widget.projectId == null
              ? jobs
              : jobs
                  .where(
                      (j) => (j.projectId ?? '').toString() == widget.projectId)
                  .toList();

          final filtered = scopedJobs.where((j) {
            return switch (_filter) {
              QueueFilter.all => true,
              QueueFilter.running => j.stage != JobStage.completed &&
                  j.stage != JobStage.failed &&
                  j.stage != JobStage.paused,
              QueueFilter.completed => j.stage == JobStage.completed,
              QueueFilter.failed => j.stage == JobStage.failed,
            };
          }).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _systemBanner(context),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeader(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: CfSegmented<QueueFilter>(
                      value: _filter,
                      onChanged: (v) => setState(() {
                        _filter = v;
                        _visibleJobs = 20;
                      }),
                      segments: const [
                        (value: QueueFilter.all, label: 'All'),
                        (value: QueueFilter.running, label: 'Running'),
                        (value: QueueFilter.completed, label: 'Completed'),
                        (value: QueueFilter.failed, label: 'Failed'),
                      ],
                    ),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: CfEmptyState(
                    icon: Icons.queue_play_next,
                    title: 'No jobs',
                    message: _filter == QueueFilter.all
                        ? 'Your processing queue is empty.'
                        : 'No ${_filter.name} jobs.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: (filtered.length > _visibleJobs
                            ? _visibleJobs
                            : filtered.length) +
                        (filtered.length > _visibleJobs ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index >=
                          (filtered.length > _visibleJobs
                              ? _visibleJobs
                              : filtered.length)) {
                        return Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleJobs += 20;
                              });
                            },
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                                'Load more (${filtered.length - _visibleJobs} left)'),
                          ),
                        );
                      }
                      final j = filtered[index];
                      return _jobCard(context, j);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _systemBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppTheme.surfaceDark,
            AppTheme.surfaceDarker,
          ],
        ),
        border: Border.all(color: cs.outline.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: -14,
            color: Colors.black.withOpacity(0.55),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'SYSTEM HEALTH',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
              ),
              const Spacer(),
              CfStatusChip(
                  label: 'Normal', color: Colors.green, icon: Icons.circle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(context,
                  icon: Icons.battery_charging_full,
                  label: 'Battery',
                  value: '68%',
                  color: cs.primary),
              const SizedBox(width: 12),
              _dividerV(context),
              const SizedBox(width: 12),
              _metric(context,
                  icon: Icons.thermostat,
                  label: 'Temp',
                  value: '42°C',
                  color: Colors.orange),
            ],
          )
        ],
      ),
    );
  }

  Widget _dividerV(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).colorScheme.outline.withOpacity(0.18),
    );
  }

  Widget _metric(BuildContext context,
      {required IconData icon,
      required String label,
      required String value,
      required Color color}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.surfaceDarker,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withOpacity(0.18)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ],
          )
        ],
      ),
    );
  }

  Widget _jobCard(BuildContext context, Job j) {
    final cs = Theme.of(context).colorScheme;

    final isRunning = j.stage == JobStage.rendering ||
        j.stage == JobStage.dubbing ||
        j.stage == JobStage.translating ||
        j.stage == JobStage.transcribing ||
        j.stage == JobStage.extractingAudio;
    final isPaused = j.stage == JobStage.paused;
    final stageLabel = jobStageLabel(j.stage);
    final stepLabel =
        (j.stepMessage != null && j.stepMessage!.trim().isNotEmpty)
            ? j.stepMessage!.trim()
            : null;

    return CfCard(
      padding: const EdgeInsets.all(0),
      onTap: () => _openJobDetails(context, j),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    CfThumbnail(
                      url: j.thumbnail,
                      width: 108,
                      height: 76,
                      overlayIcon: Icon(Icons.security, color: cs.primary),
                      opacity: j.stage == JobStage.queued ? 0.65 : 1,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            j.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isRunning
                                ? (stepLabel ?? 'Processing: $stageLabel…')
                                : stageLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: isRunning
                                      ? cs.primary
                                      : (isPaused
                                          ? Colors.orange
                                          : cs.onSurface.withOpacity(0.6)),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 14,
                                  color: cs.onSurface.withOpacity(0.55)),
                              const SizedBox(width: 6),
                              Text(
                                _formatElapsed(j.elapsed),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: cs.onSurface.withOpacity(0.55)),
                              ),
                              if (j.hasDeviceHotWarning) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.warning_amber,
                                    size: 14, color: Colors.orange.shade400),
                                const SizedBox(width: 4),
                                Text('Device hot',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Colors.orange.shade400)),
                              ],
                              if (j.hasLowBatteryWarning) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.battery_alert,
                                    size: 14, color: Colors.amber.shade400),
                                const SizedBox(width: 4),
                                Text('Low battery',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Colors.amber.shade400)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: cs.onSurface.withOpacity(0.45)),
                  ],
                ),
                const SizedBox(height: 14),
                _progressSection(context, j),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isRunning
                            ? () => _pauseJob(j.id)
                            : (isPaused ? () => _resumeJob(j.id) : null),
                        icon: Icon(isPaused ? Icons.play_arrow : Icons.pause,
                            size: 18),
                        label: Text(isPaused ? 'Resume' : 'Pause'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () => _deleteJob(j.id),
                      icon: const Icon(Icons.delete_outline),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      tooltip: 'Delete job',
                    ),
                  ],
                )
              ],
            ),
          ),
          if (isRunning)
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, cs.primary, Colors.transparent],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressSection(BuildContext context, Job j) {
    final cs = Theme.of(context).colorScheme;
    final pct = (j.progress * 100).round();

    if (j.stage == JobStage.queued) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Waiting in queue',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
          CfPill(
              label: 'Queued',
              foreground: cs.onSurface.withOpacity(0.75),
              background: cs.surfaceContainerHighest.withOpacity(0.35)),
        ],
      );
    }

    if (j.stage == JobStage.paused) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Paused by user',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
          CfPill(
              label: 'Paused',
              foreground: Colors.orange,
              background: Colors.orange.withOpacity(0.12)),
        ],
      );
    }

    if (j.stage == JobStage.completed) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Completed successfully',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
          CfPill(
              label: 'Done',
              foreground: Colors.green,
              background: Colors.green.withOpacity(0.12)),
        ],
      );
    }

    if (j.stage == JobStage.failed) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Processing failed',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
          CfPill(
              label: 'Failed',
              foreground: Colors.red,
              background: Colors.red.withOpacity(0.12)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
                j.stepMessage != null && j.stepMessage!.isNotEmpty
                    ? j.stepMessage!
                    : 'Processing',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
            const Spacer(),
            Text('$pct%',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 8),
        CfProgressBar(value: j.progress, height: 12),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Speed: ${j.speed.toStringAsFixed(1)}x',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.55),
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            Text(
              j.eta == null ? '' : 'Est: ${_formatEta(j.eta!)} remaining',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.55),
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        )
      ],
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes.toString().padLeft(2, '0')}:$s elapsed';
  }

  String _formatEta(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  void _openJobDetails(BuildContext context, Job j) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final isAi = _isAiJob(j);
        final stepProgress = isAi
            ? <double>[0.05, 0.20, 0.50, 0.80, 1.0]
            : <double>[0.10, 0.30, 0.55, 0.85, 1.0];
        final stepTitles = isAi
            ? <String>[
                'Extract audio',
                'Convert audio to text',
                'AI process text for best dialogs/scenes',
                'Segment best scenes',
                'Merge final video',
              ]
            : <String>[
                'Preparing segment',
                'Scaling and framing',
                'Applying watermark/text',
                'Encoding video/audio',
                'Finalizing output',
              ];

        final currentIdx =
            _currentInternalStepIndexByThreshold(j.progress, stepProgress);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Job details',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CfThumbnail(url: j.thumbnail, width: 88, height: 64),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(j.title,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                              jobStageLabel(j.stage),
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: cs.onSurface.withOpacity(0.65)),
                            ),
                          ],
                        ),
                      ),
                      CfStatusChip(
                        label: j.stage == JobStage.failed
                            ? 'Failed'
                            : (j.stage == JobStage.completed
                                ? 'Done'
                                : 'Running'),
                        color: j.stage == JobStage.failed
                            ? Colors.red
                            : (j.stage == JobStage.completed
                                ? Colors.green
                                : cs.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Internal Steps',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (int i = 0; i < stepTitles.length; i++)
                        _internalStepRow(
                          ctx,
                          title: stepTitles[i],
                          subtitle:
                              '${(stepProgress[i] * 100).round()}% milestone',
                          isDone:
                              (currentIdx > i) || j.stage == JobStage.completed,
                          isCurrent:
                              currentIdx == i && j.stage != JobStage.failed,
                          isFailed:
                              j.stage == JobStage.failed && currentIdx == i,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Track',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _logLine(ctx, 'Status: ${jobStageLabel(j.stage)}',
                          done: j.stage == JobStage.completed),
                      if (j.stepMessage != null && j.stepMessage!.isNotEmpty)
                        _logLine(ctx, 'Current step: ${j.stepMessage!}',
                            done: false),
                      _logLine(ctx,
                          'Progress: ${(j.progress * 100).toStringAsFixed(0)}%',
                          done: j.stage == JobStage.completed),
                      _logLine(ctx,
                          'ETA: ${j.eta == null ? 'Calculating...' : _formatEta(j.eta!)}',
                          done: false),
                      _logLine(ctx, 'Elapsed: ${_formatElapsed(j.elapsed)}',
                          done: false),
                      if (j.hasDeviceHotWarning)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber,
                                  size: 16, color: Colors.orange.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Device hot. Performance may be throttled.',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Colors.orange.shade400,
                                          fontWeight: FontWeight.w700),
                                ),
                              )
                            ],
                          ),
                        )
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (j.stage == JobStage.completed)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openVideoFromJob(j),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Open Video'),
                        ),
                      ),
                    if (j.stage == JobStage.completed)
                      const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: j.stage == JobStage.failed
                            ? () {
                                Navigator.pop(ctx);
                                _retryJob(j.id);
                              }
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteJob(j.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  int _currentInternalStepIndex(double progress) {
    if (progress < 0.10) return 0;
    if (progress < 0.30) return 1;
    if (progress < 0.55) return 2;
    if (progress < 0.85) return 3;
    return 4;
  }

  int _currentInternalStepIndexByThreshold(
      double progress, List<double> thresholds) {
    for (int i = 0; i < thresholds.length; i++) {
      if (progress < thresholds[i]) return i;
    }
    return thresholds.length - 1;
  }

  bool _isAiJob(Job j) {
    final msg = (j.stepMessage ?? '').toLowerCase();
    final out = (j.outputFilename ?? '').toLowerCase();
    return msg.contains('transcript') ||
        msg.contains('audio') ||
        msg.contains('scene') ||
        msg.contains('merge') ||
        out.contains('best_scenes');
  }

  Widget _internalStepRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isCurrent,
    required bool isFailed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = isFailed
        ? Colors.red
        : isDone
            ? Colors.green
            : (isCurrent ? cs.primary : cs.onSurface.withOpacity(0.35));
    final icon = isFailed
        ? Icons.error
        : isDone
            ? Icons.check_circle
            : (isCurrent ? Icons.timelapse : Icons.radio_button_unchecked);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isCurrent ? cs.onSurface : cs.onSurface.withOpacity(0.8),
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: cs.onSurface.withOpacity(0.55)),
      ),
    );
  }

  Widget _stepRow(BuildContext context, JobStage stage,
      {required bool isDone, required bool isCurrent}) {
    final cs = Theme.of(context).colorScheme;
    final color = isDone
        ? Colors.green
        : (isCurrent ? cs.primary : cs.onSurface.withOpacity(0.35));
    final icon = isDone
        ? Icons.check_circle
        : (isCurrent ? Icons.timelapse : Icons.radio_button_unchecked);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              jobStageLabel(stage),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? cs.onSurface
                        : cs.onSurface.withOpacity(0.75),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logLine(BuildContext context, String text, {bool done = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(done ? Icons.check : Icons.circle,
              size: 12,
              color: done ? Colors.green : cs.onSurface.withOpacity(0.25)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.75),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pauseJob(String jobId) async {
    try {
      await _api.updateJob(jobId: jobId, status: 'paused');
      await _syncService.refreshJobsNow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not pause job: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resumeJob(String jobId) async {
    try {
      await _api.updateJob(jobId: jobId, status: 'running');
      await _syncService.refreshJobsNow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not resume job: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteJob(String jobId) async {
    try {
      await _api.deleteJob(jobId);
      await _syncService.refreshJobsNow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not delete job: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openVideoFromJob(Job j) async {
    final path = j.outputPath;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video path is not available yet for this job'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPreviewScreen(
          videoPath: path,
          title: j.outputFilename ?? j.title,
        ),
      ),
    );
  }

  Future<void> _retryJob(String jobId) async {
    try {
      await _api.updateJob(jobId: jobId, status: 'pending', progress: 0.0);
      await LocalQueueDb().updateJobStatus(
        jobId,
        local_job.JobStatus.pending,
        progress: 0.0,
      );
      await _syncService.refreshJobsNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job moved back to queue')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not retry job: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Container(color: bg.withOpacity(0.96), child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
