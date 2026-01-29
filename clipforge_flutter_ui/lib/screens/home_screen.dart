import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'create_shorts_wizard.dart';
import 'create_summary_wizard.dart';
import 'project_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final List<Project> _recentProjects = [
    Project(
      id: 'p1',
      title: 'Podcast Ep 42',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      duration: const Duration(minutes: 20),
      status: ProjectStatus.completed,
      thumbnail: 'https://images.unsplash.com/photo-1525182008055-f88b95ff7980?w=800&q=80',
      shortsCount: 12,
      languages: const ['EN', 'HI', 'UR'],
    ),
    Project(
      id: 'p2',
      title: 'Gaming Stream Highlights',
      createdAt: DateTime.now().subtract(const Duration(hours: 10)),
      duration: const Duration(hours: 2, minutes: 12),
      status: ProjectStatus.processing,
      thumbnail: 'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=800&q=80',
      shortsCount: 0,
      languages: const ['EN'],
    ),
    Project(
      id: 'p3',
      title: 'Vlog Raw Footage',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 58),
      status: ProjectStatus.draft,
      thumbnail: 'https://images.unsplash.com/photo-1526481280695-3c687fd5432c?w=800&q=80',
      shortsCount: 0,
      languages: const ['EN'],
    ),
    Project(
      id: 'p4',
      title: 'Workshop Recording',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(hours: 1, minutes: 35),
      status: ProjectStatus.failed,
      thumbnail: 'https://images.unsplash.com/photo-1553877522-43269d4ea984?w=800&q=80',
      shortsCount: 0,
      languages: const ['EN', 'HI'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CfAppBar(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [cs.primary, Colors.blue.shade600],
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    spreadRadius: -10,
                    color: cs.primary.withOpacity(0.35),
                  )
                ],
              ),
              child: const Icon(Icons.movie_filter, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              'ClipForge',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: CfPill(
                label: 'MODELS READY',
                icon: Icons.circle,
                background: cs.surface.withOpacity(0.60),
                foreground: cs.primary,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showImportSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Import Video'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _storageChip(context),
          const SizedBox(height: 18),
          Text(
            'Start Creating',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          _heroCard(
            context,
            title: 'Create Shorts',
            subtitle: 'Turn long videos into vertical Shorts/Reels.',
            icon: Icons.content_cut,
            imageUrl:
                'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?w=1200&q=80',
            primary: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateShortsWizard()),
            ),
          ),
          const SizedBox(height: 12),
          _heroCard(
            context,
            title: 'Create Summary Video',
            subtitle: 'Extract key moments and create highlights.',
            icon: Icons.summarize,
            imageUrl:
                'https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=1200&q=80',
            primary: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateSummaryWizard()),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Projects',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Open Projects tab to view all.')),
                  );
                },
                child: const Text('View All'),
              )
            ],
          ),
          const SizedBox(height: 8),
          ..._recentProjects.take(5).map((p) => _recentProjectTile(context, p)),
        ],
      ),
    );
  }

  Widget _storageChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        CfPill(
          label: '5.2GB ON-DEVICE USED',
          icon: Icons.sd_storage,
          background: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.surfaceDarker
              : Colors.black.withOpacity(0.04),
          foreground: cs.onSurface.withOpacity(0.75),
          border: BorderSide(color: cs.outline.withOpacity(0.25)),
          textStyle: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none),
          tooltip: 'Notifications',
        ),
      ],
    );
  }

  Widget _heroCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String imageUrl,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outline.withOpacity(0.18)),
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              spreadRadius: -12,
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.12,
              ),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 168,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(imageUrl, fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          cs.surface.withOpacity(0.90),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.40),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(icon, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: primary
                        ? FilledButton.icon(
                            onPressed: onTap,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Start'),
                          )
                        : OutlinedButton.icon(
                            onPressed: onTap,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
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

  Widget _recentProjectTile(BuildContext context, Project p) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('MMM d • h:mm a');
    final statusColor = projectStatusColor(p.status, cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CfCard(
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)),
        ),
        child: Row(
          children: [
            CfThumbnail(
              url: p.thumbnail,
              width: 88,
              height: 64,
              badge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${p.duration.inMinutes}m',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    df.format(p.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.55),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CfStatusChip(
              label: projectStatusLabel(p.status).toUpperCase(),
              color: statusColor,
              icon: switch (p.status) {
                ProjectStatus.completed => Icons.check_circle,
                ProjectStatus.processing => Icons.auto_mode,
                ProjectStatus.failed => Icons.error,
                ProjectStatus.draft => Icons.edit,
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Import video',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'ClipForge processes locally on your device. No uploads.',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.65)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateShortsWizard()),
                    );
                  },
                  icon: const Icon(Icons.content_cut),
                  label: const Text('Create Shorts'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateSummaryWizard()),
                    );
                  },
                  icon: const Icon(Icons.summarize),
                  label: const Text('Create Summary Video'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
