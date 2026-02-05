import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/project_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'create_shorts_wizard.dart';
import 'project_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _syncService = ProjectSyncService();
  List<Project> _recentProjects = const [];
  bool _isLoadingRecent = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentProjects();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecentProjects();
    }
  }

  Future<void> _loadRecentProjects() async {
    setState(() {
      _isLoadingRecent = true;
    });

    try {
      final backendProjects = await _syncService.fetchProjectsOnce();
      final projects =
          backendProjects.map((json) => Project.fromBackendMap(json)).toList();
      if (!mounted) return;
      setState(() {
        _recentProjects = projects.take(4).toList();
        _isLoadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recentProjects = const [];
        _isLoadingRecent = false;
      });
    }
  }

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
            title: 'Create Videos',
            subtitle:
                'Split videos or create AI summaries with 6 modes to choose from.',
            icon: Icons.movie_creation,
            imageUrl:
                'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?w=1200&q=80',
            primary: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateShortsWizard()),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quickActionCard(
                  context,
                  title: 'Split Videos',
                  subtitle: '3 modes',
                  icon: Icons.content_cut,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const CreateShortsWizard(initialCategory: 'split'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickActionCard(
                  context,
                  title: 'AI Summary',
                  subtitle: '3 AI modes',
                  icon: Icons.auto_awesome,
                  color: Colors.purple,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const CreateShortsWizard(initialCategory: 'summary'),
                    ),
                  ),
                ),
              ),
            ],
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
                    const SnackBar(
                        content: Text('Open Projects tab to view all.')),
                  );
                },
                child: const Text('View All'),
              )
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingRecent)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentProjects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No projects yet. Start your first split.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                    ),
              ),
            )
          else
            ..._recentProjects.map((p) => _recentProjectTile(context, p)),
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

  Widget _quickActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = color ?? cs.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withOpacity(0.18)),
          color: cs.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cardColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                  ),
            ),
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
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose from 6 modes: Split videos or create AI summaries.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.65)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const CreateShortsWizard()),
                    );
                  },
                  icon: const Icon(Icons.movie_creation),
                  label: const Text('Start Creating'),
                ),
                const SizedBox(height: 10),
                Text(
                  'All processing happens on your device. No uploads required.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.55),
                        fontStyle: FontStyle.italic,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
