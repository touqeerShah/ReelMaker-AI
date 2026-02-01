import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../services/auth_service.dart';
import 'social_media_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<ModelAsset> _models;
  final _auth = AuthService();

  bool _onlyWhileCharging = false;
  bool _pauseLowBattery = true;
  bool _limitConcurrent = true;
  bool _wifiForModelsOnly = true;

  String _defaultFrom = 'English';
  String _defaultTo = 'Hindi';
  bool _watermarkEnabled = false;

  @override
  void initState() {
    super.initState();
    _models = [
      ModelAsset(
        id: 'whisper',
        name: 'Whisper v3',
        subtitle: 'Speech-to-Text Engine',
        sizeLabel: '480 MB',
        icon: Icons.graphic_eq,
        status: ModelStatus.ready,
      ),
      ModelAsset(
        id: 'phi3',
        name: 'Phi-3 Mini',
        subtitle: 'Reasoning & Summarization',
        sizeLabel: '2.8 GB',
        icon: Icons.psychology,
        status: ModelStatus.updateAvailable,
      ),
      ModelAsset(
        id: 'whisper_small',
        name: 'Whisper (small)',
        subtitle: 'Higher accuracy, slower',
        sizeLabel: '1.0 GB',
        icon: Icons.record_voice_over,
        status: ModelStatus.notInstalled,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CfAppBar(title: Text('Settings & Models')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          CfGradientBanner(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Icon(Icons.security, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Protected',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'All processing runs on your device. No video data ever leaves your phone.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                            ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          CfCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: widget.themeMode,
                  onChanged: (v) => widget.onThemeModeChanged(v!),
                  title: const Text('Dark (default)'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: widget.themeMode,
                  onChanged: (v) => widget.onThemeModeChanged(v!),
                  title: const Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: widget.themeMode,
                  onChanged: (v) => widget.onThemeModeChanged(v!),
                  title: const Text('System'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _storageSection(context),
          const SizedBox(height: 18),
          Text(
            'Models',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ..._models.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _modelCard(context, m),
              )),
          const SizedBox(height: 18),
          Text(
            'Processing constraints',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          Text(
            'Publishing',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SocialMediaScreen()),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: CfCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.share, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Social Media Accounts',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage auto-posting settings',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Account',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          CfCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.logout, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sign out',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async => _auth.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          CfCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                CfToggleTile(
                  leading: const Icon(Icons.power),
                  title: 'Only process while charging',
                  subtitle: 'Prevents battery drain during heavy renders',
                  value: _onlyWhileCharging,
                  onChanged: (v) => setState(() => _onlyWhileCharging = v),
                ),
                const Divider(height: 1),
                CfToggleTile(
                  leading: const Icon(Icons.battery_alert),
                  title: 'Pause on low battery',
                  subtitle: 'Auto-pause jobs at 20% battery',
                  value: _pauseLowBattery,
                  onChanged: (v) => setState(() => _pauseLowBattery = v),
                ),
                const Divider(height: 1),
                CfToggleTile(
                  leading: const Icon(Icons.layers),
                  title: 'Limit concurrent jobs',
                  subtitle: 'Max 1–2 videos per batch',
                  value: _limitConcurrent,
                  onChanged: (v) => setState(() => _limitConcurrent = v),
                ),
                const Divider(height: 1),
                CfToggleTile(
                  leading: const Icon(Icons.wifi),
                  title: 'Only on Wi‑Fi (model downloads)',
                  subtitle: 'Applies to model downloads only',
                  value: _wifiForModelsOnly,
                  onChanged: (v) => setState(() => _wifiForModelsOnly = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Defaults',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          CfCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Language defaults', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _dropdown(context, 'From', _defaultFrom, const ['English', 'Hindi', 'Urdu'], (v) => setState(() => _defaultFrom = v))),
                    const SizedBox(width: 10),
                    Expanded(child: _dropdown(context, 'To', _defaultTo, const ['English', 'Hindi', 'Urdu'], (v) => setState(() => _defaultTo = v))),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Watermark', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _watermarkEnabled,
                  onChanged: (v) => setState(() => _watermarkEnabled = v),
                  title: const Text('Enable watermark by default'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Local-only banner',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          CfCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.lock, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'All processing runs on your device.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Storage usage',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Text(
              '3.3GB Used',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: cs.primary),
            )
          ],
        ),
        const SizedBox(height: 8),
        CfCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Text('AI Models Space Allocation', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('128GB total', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55), fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 10),
              CfProgressBar(value: 0.15, height: 12),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text('3.3GB of 128GB used', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55))),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _modelCard(BuildContext context, ModelAsset m) {
    final cs = Theme.of(context).colorScheme;

    Color accent;
    Widget trailing;

    switch (m.status) {
      case ModelStatus.ready:
        accent = Colors.green;
        trailing = CfStatusChip(label: 'Ready', color: accent, icon: Icons.circle);
        break;
      case ModelStatus.downloading:
        accent = cs.primary;
        trailing = CfStatusChip(label: 'Downloading', color: accent, icon: Icons.downloading);
        break;
      case ModelStatus.updateAvailable:
        accent = cs.primary;
        trailing = CfStatusChip(label: 'Update', color: accent, icon: Icons.downloading);
        break;
      case ModelStatus.notInstalled:
        accent = cs.onSurface.withOpacity(0.55);
        trailing = CfStatusChip(label: 'Not installed', color: Colors.grey, icon: Icons.cloud_download);
        break;
    }

    return CfCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Icon(m.icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(m.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Size: ${m.sizeLabel}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55), fontFamily: 'monospace')),
              const Spacer(),
              if (m.status == ModelStatus.ready)
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove model',
                )
              else
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.cloud_download, size: 18),
                  label: Text(m.status == ModelStatus.updateAvailable ? 'Update' : 'Download'),
                )
            ],
          )
        ],
      ),
    );
  }

  Widget _dropdown(BuildContext context, String label, String value, List<String> values, ValueChanged<String> onChanged) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.9, fontWeight: FontWeight.w900, color: cs.onSurface.withOpacity(0.55))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: values.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ],
    );
  }
}
