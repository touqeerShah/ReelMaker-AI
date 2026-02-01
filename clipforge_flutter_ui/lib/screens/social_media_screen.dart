import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class SocialMediaScreen extends StatefulWidget {
  const SocialMediaScreen({super.key});

  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen> {
  String _postingMode = 'immediate'; // immediate, batch, scheduled
  String _scheduleType = 'daily'; // hourly, daily, weekly
  int _videosPerPeriod = 1; // how many videos per period
  
  final _platforms = [
    {'name': 'TikTok', 'icon': Icons.music_note, 'color': Color(0xFF000000), 'connected': false},
    {'name': 'YouTube Shorts', 'icon': Icons.play_circle_filled, 'color': Color(0xFFFF0000), 'connected': false},
    {'name': 'Instagram Reels', 'icon': Icons.camera_alt, 'color': Color(0xFFE4405F), 'connected': true},
    {'name': 'Facebook', 'icon': Icons.facebook, 'color': Color(0xFF1877F2), 'connected': false},
    {'name': 'Twitter/X', 'icon': Icons.close, 'color': Color(0xFF000000), 'connected': false},
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CfAppBar(title: Text('Social Media Publishing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Text(
            'Connected Accounts',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Link your social media accounts to automatically publish your shorts',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),

          // Platform cards
          ..._platforms.map((platform) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlatformCard(
              name: platform['name'] as String,
              icon: platform['icon'] as IconData,
              color: platform['color'] as Color,
              isConnected: platform['connected'] as bool,
              onToggle: () {
                setState(() {
                  platform['connected'] = !(platform['connected'] as bool);
                });
              },
            ),
          )),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          // Auto-posting settings
          Text(
            'Auto-Posting Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // Posting mode selector
          _PostingModeCard(
            title: 'Upload Immediately',
            subtitle: 'Post each short as soon as it\'s ready',
            icon: Icons.flash_on,
            isSelected: _postingMode == 'immediate',
            onTap: () => setState(() => _postingMode = 'immediate'),
          ),
          const SizedBox(height: 12),
          
          _PostingModeCard(
            title: 'Batch Upload',
            subtitle: 'Upload all shorts at once when processing is complete',
            icon: Icons.collections,
            isSelected: _postingMode == 'batch',
            onTap: () => setState(() => _postingMode = 'batch'),
          ),
          const SizedBox(height: 12),
          
          _PostingModeCard(
            title: 'Scheduled Intervals',
            subtitle: 'Post shorts at fixed time intervals',
            icon: Icons.schedule,
            isSelected: _postingMode == 'scheduled',
            onTap: () => setState(() => _postingMode = 'scheduled'),
          ),

          // Interval settings (only show if scheduled mode)
          if (_postingMode == 'scheduled') ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Posting Frequency',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Schedule type dropdown
                  DropdownButtonFormField<String>(
                    value: _scheduleType,
                    decoration: InputDecoration(
                      labelText: 'Schedule Type',
                      filled: true,
                      fillColor: AppTheme.surfaceDarker,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'hourly',
                        child: Text('Hourly'),
                      ),
                      DropdownMenuItem(
                        value: 'daily',
                        child: Text('Daily'),
                      ),
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text('Weekly'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _scheduleType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Videos per period
                  DropdownButtonFormField<int>(
                    value: _videosPerPeriod,
                    decoration: InputDecoration(
                      labelText: 'Videos per ${_scheduleType == "hourly" ? "hour" : _scheduleType == "daily" ? "day" : "week"}',
                      filled: true,
                      fillColor: AppTheme.surfaceDarker,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                    items: List.generate(10, (i) => i + 1).map((count) {
                      return DropdownMenuItem<int>(
                        value: count,
                        child: Text('$count ${count == 1 ? "video" : "videos"}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _videosPerPeriod = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getFrequencyDescription(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          
          // Save button
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Auto-posting settings saved!')),
                );
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Save Settings'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getFrequencyDescription() {
    final videoText = _videosPerPeriod == 1 ? 'video' : 'videos';
    switch (_scheduleType) {
      case 'hourly':
        return '$_videosPerPeriod $videoText will be posted every hour';
      case 'daily':
        if (_videosPerPeriod == 1) {
          return 'One video will be posted every 24 hours';
        } else {
          final hours = 24 ~/ _videosPerPeriod;
          return '$_videosPerPeriod videos posted daily (every ~$hours hours)';
        }
      case 'weekly':
        return '$_videosPerPeriod $videoText will be posted every week';
      default:
        return '';
    }
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.isConnected,
    required this.onToggle,
  });

  final String name;
  final IconData icon;
  final Color color;
  final bool isConnected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected 
            ? AppTheme.primary.withOpacity(0.3)
            : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isConnected ? 'Connected' : 'Not connected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isConnected 
                            ? AppTheme.primary
                            : cs.onSurface.withOpacity(0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 52,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isConnected ? AppTheme.primary : Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: isConnected ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostingModeCard extends StatelessWidget {
  const _PostingModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected 
            ? AppTheme.primary
            : Colors.white.withOpacity(0.05),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected 
                      ? AppTheme.primary.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected 
                        ? AppTheme.primary
                        : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Icon(
                    icon, 
                    color: isSelected ? AppTheme.primary : cs.onSurface,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? AppTheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: AppTheme.primary,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
