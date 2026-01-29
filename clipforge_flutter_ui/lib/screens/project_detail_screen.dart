import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/widgets.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  int _langIdx = 0;

  final List<String> _variants = const ['English (Orig)', 'Hindi (Dub)', 'Urdu (Dub)'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CfAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            Text(
              '${widget.project.duration.inMinutes}m • ${projectStatusLabel(widget.project.status)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export/Share',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _player(context),
          const SizedBox(height: 12),
          _languageSwitcher(context),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('Generated Clips', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              CfPill(label: '3 Ready', foreground: cs.primary),
            ],
          ),
          const SizedBox(height: 10),
          _clipTimeline(context),
          const SizedBox(height: 18),
          Text('Actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          CfCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.replay),
                  title: const Text('Re-render'),
                  subtitle: Text('Change presets, subtitles, or dubs', style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete outputs'),
                  subtitle: Text('Free up storage on-device', style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _player(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(widget.project.thumbnail, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                ),
              ),
            ),
            Center(
              child: FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary.withOpacity(0.92),
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                child: const Icon(Icons.play_arrow, size: 30),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 12,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('00:15', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(
                        _formatDuration(widget.project.duration),
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: 0.15,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.20),
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _languageSwitcher(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(_variants.length, (i) {
          final selected = i == _langIdx;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _langIdx = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _variants[i],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.black : cs.onSurface.withOpacity(0.55),
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle, size: 16, color: Colors.black),
                    ]
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _clipTimeline(BuildContext context) {
    final clips = const [
      (title: 'The Intro & Setup', range: '00:00 - 00:45', len: '00:45', score: 98, thumb: 'https://images.unsplash.com/photo-1525182008055-f88b95ff7980?w=800&q=80'),
      (title: 'Key Argument', range: '05:10 - 06:10', len: '01:00', score: 86, thumb: 'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=800&q=80'),
      (title: 'Closing Takeaway', range: '13:20 - 14:05', len: '00:45', score: 91, thumb: 'https://images.unsplash.com/photo-1553877522-43269d4ea984?w=800&q=80'),
    ];

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: clips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = clips[i];
          return SizedBox(
            width: 200,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openClipVariants(context, c.title),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(c.thumb, fit: BoxFit.cover),
                          Container(color: Colors.black.withOpacity(0.18)),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                c.len,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.trending_up, size: 12, color: Colors.black),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${c.score}',
                                    style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    c.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.range,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openClipVariants(BuildContext context, String clipTitle) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(clipTitle, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                CfCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _variantRow(ctx, 'EN subtitles', 'Burned-in captions', Icons.subtitles, cs.primary),
                      const Divider(height: 1),
                      _variantRow(ctx, 'HI dub', 'Voice: Asha', Icons.record_voice_over, Colors.orange),
                      const Divider(height: 1),
                      _variantRow(ctx, 'UR dub', 'Voice: Zain', Icons.record_voice_over, Colors.amber),
                      const Divider(height: 1),
                      _variantRow(ctx, 'YouTube Shorts preset', '1080x1920 • 60fps', Icons.smart_display, cs.primary),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Export/Share'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete output'),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _variantRow(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }
}
