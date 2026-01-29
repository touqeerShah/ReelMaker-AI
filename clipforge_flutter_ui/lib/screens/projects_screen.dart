import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../widgets/widgets.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  static final List<Project> _projects = List.generate(12, (i) {
    final status = switch (i % 4) {
      0 => ProjectStatus.completed,
      1 => ProjectStatus.processing,
      2 => ProjectStatus.draft,
      _ => ProjectStatus.failed,
    };
    return Project(
      id: 'p$i',
      title: 'Project #${i + 1}',
      createdAt: DateTime.now().subtract(Duration(hours: 2 * i)),
      duration: Duration(minutes: 12 + (i * 7)),
      status: status,
      thumbnail: 'https://images.unsplash.com/photo-1525182008055-f88b95ff7980?w=800&q=80&sig=$i',
      shortsCount: status == ProjectStatus.completed ? 6 + i : 0,
      languages: status == ProjectStatus.completed
          ? const ['EN', 'HI', 'UR']
          : const ['EN'],
    );
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('MMM d');

    return Scaffold(
      appBar: const CfAppBar(title: Text('Projects')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemBuilder: (context, index) {
          final p = _projects[index];
          final statusColor = projectStatusColor(p.status, cs);

          return CfCard(
            padding: const EdgeInsets.all(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)),
            ),
            child: Row(
              children: [
                CfThumbnail(url: p.thumbnail, width: 104, height: 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: cs.onSurface.withOpacity(0.55)),
                          const SizedBox(width: 6),
                          Text(
                            '${p.duration.inMinutes}m • ${df.format(p.createdAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurface.withOpacity(0.55)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          CfStatusChip(label: projectStatusLabel(p.status), color: statusColor),
                          if (p.shortsCount > 0) CfPill(label: '${p.shortsCount} shorts'),
                          CfPill(label: p.languages.join(' / ')),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.5)),
              ],
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _projects.length,
      ),
    );
  }
}
