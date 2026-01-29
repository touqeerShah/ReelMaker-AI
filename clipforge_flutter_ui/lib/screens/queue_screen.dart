import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

enum QueueFilter { all, running, completed, failed }

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  QueueFilter _filter = QueueFilter.running;

  late List<Job> _jobs;

  @override
  void initState() {
    super.initState();
    _jobs = [
      Job(
        id: 'j1',
        title: 'Podcast_Ep42_Raw.mp4',
        thumbnail: 'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?w=1000&q=80',
        stage: JobStage.transcribing,
        progress: 0.45,
        elapsed: const Duration(minutes: 4, seconds: 20),
        speed: 1.2,
        eta: const Duration(minutes: 12),
      ),
      Job(
        id: 'j2',
        title: 'Meeting_QuarterlyReview.mp4',
        thumbnail: 'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?w=1000&q=80',
        stage: JobStage.queued,
        progress: 0.0,
        elapsed: const Duration(seconds: 0),
      ),
      Job(
        id: 'j3',
        title: 'Vlog_TravelDay1.mov',
        thumbnail: 'https://images.unsplash.com/photo-1526481280695-3c687fd5432c?w=1000&q=80',
        stage: JobStage.completed,
        progress: 1.0,
        elapsed: const Duration(minutes: 18, seconds: 2),
      ),
      Job(
        id: 'j4',
        title: 'Workshop_Recording.mp4',
        thumbnail: 'https://images.unsplash.com/photo-1553877522-43269d4ea984?w=1000&q=80',
        stage: JobStage.failed,
        progress: 0.62,
        elapsed: const Duration(minutes: 6, seconds: 11),
        hasDeviceHotWarning: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = _jobs.where((j) {
      return switch (_filter) {
        QueueFilter.all => true,
        QueueFilter.running => j.stage != JobStage.completed && j.stage != JobStage.failed,
        QueueFilter.completed => j.stage == JobStage.completed,
        QueueFilter.failed => j.stage == JobStage.failed,
      };
    }).toList();

    return Scaffold(
      appBar: CfAppBar(
        title: const Text('Processing Queue'),
        actions: [
          TextButton(
            onPressed: _jobs.isEmpty
                ? null
                : () => setState(() {
                      _jobs.clear();
                    }),
            child: const Text('Clear All'),
          )
        ],
      ),
      body: CustomScrollView(
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
                  onChanged: (v) => setState(() => _filter = v),
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
                message: 'Your processing queue is empty.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final j = filtered[index];
                  return _jobCard(context, j);
                },
              ),
            ),
        ],
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
              CfStatusChip(label: 'Normal', color: Colors.green, icon: Icons.circle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(context, icon: Icons.battery_charging_full, label: 'Battery', value: '68%', color: cs.primary),
              const SizedBox(width: 12),
              _dividerV(context),
              const SizedBox(width: 12),
              _metric(context, icon: Icons.thermostat, label: 'Temp', value: '42°C', color: Colors.orange),
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

  Widget _metric(BuildContext context, {required IconData icon, required String label, required String value, required Color color}) {
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
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6))),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            ],
          )
        ],
      ),
    );
  }

  Widget _jobCard(BuildContext context, Job j) {
    final cs = Theme.of(context).colorScheme;

    final isRunning = j.stage != JobStage.completed && j.stage != JobStage.failed;
    final stageLabel = jobStageLabel(j.stage);

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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isRunning ? 'Step 2/4: $stageLabel…' : stageLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: isRunning ? cs.primary : cs.onSurface.withOpacity(0.6),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 14, color: cs.onSurface.withOpacity(0.55)),
                              const SizedBox(width: 6),
                              Text(
                                _formatElapsed(j.elapsed),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55)),
                              ),
                              if (j.hasDeviceHotWarning) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade400),
                                const SizedBox(width: 4),
                                Text('Device hot', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange.shade400)),
                              ],
                              if (j.hasLowBatteryWarning) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.battery_alert, size: 14, color: Colors.amber.shade400),
                                const SizedBox(width: 4),
                                Text('Low battery', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber.shade400)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.45)),
                  ],
                ),
                const SizedBox(height: 14),
                _progressSection(context, j),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isRunning ? () {} : null,
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('Pause'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () {
                        setState(() => _jobs.removeWhere((x) => x.id == j.id));
                      },
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      tooltip: 'Cancel',
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ),
          CfPill(label: 'Queued', foreground: cs.onSurface.withOpacity(0.75), background: cs.surfaceContainerHighest.withOpacity(0.35)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Processing', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6))),
            const Spacer(),
            Text('$pct%', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 8),
        CfProgressBar(value: j.progress, height: 12),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Speed: ${j.speed.toStringAsFixed(1)}x', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55), fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            Text(
              j.eta == null ? '' : 'Est: ${_formatEta(j.eta!)} remaining',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55), fontFeatures: const [FontFeature.tabularFigures()]),
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
        final steps = const [
          JobStage.extractingAudio,
          JobStage.transcribing,
          JobStage.translating,
          JobStage.dubbing,
          JobStage.rendering,
        ];

        final currentIdx = steps.indexWhere((s) => s == j.stage);

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
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
                            Text(j.title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                              jobStageLabel(j.stage),
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65)),
                            ),
                          ],
                        ),
                      ),
                      CfStatusChip(
                        label: j.stage == JobStage.failed ? 'Failed' : (j.stage == JobStage.completed ? 'Done' : 'Running'),
                        color: j.stage == JobStage.failed
                            ? Colors.red
                            : (j.stage == JobStage.completed ? Colors.green : cs.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Steps', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (int i = 0; i < steps.length; i++)
                        _stepRow(ctx, steps[i], isDone: (currentIdx > i) || j.stage == JobStage.completed, isCurrent: currentIdx == i),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Logs', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _logLine(ctx, 'Extracting audio…', done: currentIdx > 0),
                      _logLine(ctx, 'Running Whisper STT…', done: currentIdx > 1),
                      _logLine(ctx, 'Translating to HI/UR…', done: currentIdx > 2),
                      _logLine(ctx, 'Rendering vertical clips…', done: currentIdx > 4),
                      if (j.hasDeviceHotWarning)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Device hot. Performance may be throttled.',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.orange.shade400, fontWeight: FontWeight.w700),
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
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: j.stage == JobStage.failed ? () {} : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _jobs.removeWhere((x) => x.id == j.id));
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

  Widget _stepRow(BuildContext context, JobStage stage, {required bool isDone, required bool isCurrent}) {
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
                    color: isCurrent ? cs.onSurface : cs.onSurface.withOpacity(0.75),
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
          Icon(done ? Icons.check : Icons.circle, size: 12, color: done ? Colors.green : cs.onSurface.withOpacity(0.25)),
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Container(color: bg.withOpacity(0.96), child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) => false;
}
