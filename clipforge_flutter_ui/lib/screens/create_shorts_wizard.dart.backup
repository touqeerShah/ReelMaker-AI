import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class CreateShortsWizard extends StatefulWidget {
  const CreateShortsWizard({super.key});

  @override
  State<CreateShortsWizard> createState() => _CreateShortsWizardState();
}

class _CreateShortsWizardState extends State<CreateShortsWizard> {
  final PageController _controller = PageController();
  int _step = 0;

  // State placeholders (UI only)
  final List<String> _selectedVideos = ['Podcast_Ep42_Raw.mp4'];
  int _fixedDuration = 45;
  bool _smartSplit = true;

  bool _subtitles = true;
  double _subtitleFont = 16;
  String _subtitlePosition = 'Bottom';
  bool _subtitleBg = true;

  bool _autoDetectSource = true;
  String _sourceOverride = 'English';
  final Set<String> _targetLangs = {'Hindi', 'Urdu'};

  bool _dubAudio = false;
  final Map<String, String> _voiceByLang = {'Hindi': 'Asha', 'Urdu': 'Zain'};

  bool _watermark = false;
  String _wmPos = 'Bottom-right';
  double _wmOpacity = 0.6;

  String _preset = 'YouTube Shorts';
  String _quality = 'Balanced';

  static const _steps = <String>[
    'Select video',
    'Split method',
    'Subtitles',
    'Translation',
    'Dubbing',
    'Branding',
    'Output',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CfAppBar(
        title: const Text('Create Shorts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Stepper header (matches the template's step meter).
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.96),
              border: Border(bottom: BorderSide(color: cs.outline.withOpacity(0.12))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'STEP ${_step + 1} OF ${_steps.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      _steps[_step],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CfStepDots(total: _steps.length, current: _step),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepSelectVideos(context),
                _stepSplit(context),
                _stepSubtitles(context),
                _stepTranslation(context),
                _stepDubbing(context),
                _stepBranding(context),
                _stepOutput(context),
              ],
            ),
          ),
          _bottomBar(context),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final isLast = _step == _steps.length - 1;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.96),
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.12))),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _step == 0 ? null : _back,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isLast ? _startProcessing : _next,
                child: Text(isLast ? 'Start Processing' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    if (_step >= _steps.length - 1) return;
    setState(() => _step++);
    _controller.animateToPage(_step, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _back() {
    if (_step <= 0) return;
    setState(() => _step--);
    _controller.animateToPage(_step, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _startProcessing() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Queued'),
          content: const Text('This is a UI prototype. Your job would be added to the Queue.\n\nOn-device: estimated 1.4GB temporary storage.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        );
      },
    );
  }

  // --- Step 1
  Widget _stepSelectVideos(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Select video(s)', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose one or more videos from device storage (UI placeholder).', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final v in _selectedVideos)
                ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Local file'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selectedVideos.remove(v)),
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.add, color: cs.primary),
                title: const Text('Add more videos'),
                subtitle: const Text('Multi-select supported'),
                onTap: () {
                  setState(() => _selectedVideos.add('NewVideo_${_selectedVideos.length + 1}.mp4'));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 2
  Widget _stepSplit(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Choose split method', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Fixed duration or smart splitting based on summary evidence.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fixed duration', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  for (final d in const [30, 45, 60])
                    ChoiceChip(
                      selected: _fixedDuration == d,
                      label: Text('${d}s'),
                      onSelected: (_) => setState(() => _fixedDuration = d),
                    )
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Smart split', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('Use Summary Evidence', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65))),
                      ],
                    ),
                  ),
                  Switch.adaptive(value: _smartSplit, onChanged: (v) => setState(() => _smartSplit = v)),
                ],
              )
            ],
          ),
        )
      ],
    );
  }

  // --- Step 3
  Widget _stepSubtitles(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Subtitles', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Generate subtitles and adjust styling.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _subtitles,
                onChanged: (v) => setState(() => _subtitles = v),
                title: const Text('Generate subtitles', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('On-device transcription via Whisper'),
              ),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Opacity(
                opacity: _subtitles ? 1 : 0.5,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _subtitlePosition,
                            items: const [
                              DropdownMenuItem(value: 'Bottom', child: Text('Bottom')),
                              DropdownMenuItem(value: 'Center', child: Text('Center')),
                              DropdownMenuItem(value: 'Top', child: Text('Top')),
                            ],
                            onChanged: _subtitles ? (v) => setState(() => _subtitlePosition = v!) : null,
                            decoration: const InputDecoration(labelText: 'Position'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _subtitleBg ? 'Background on' : 'Background off',
                            items: const [
                              DropdownMenuItem(value: 'Background on', child: Text('Background on')),
                              DropdownMenuItem(value: 'Background off', child: Text('Background off')),
                            ],
                            onChanged: _subtitles
                                ? (v) => setState(() => _subtitleBg = v == 'Background on')
                                : null,
                            decoration: const InputDecoration(labelText: 'Background'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Font size', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text('${_subtitleFont.round()}px', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65))),
                      ],
                    ),
                    Slider(
                      value: _subtitleFont,
                      min: 12,
                      max: 28,
                      divisions: 16,
                      onChanged: _subtitles ? (v) => setState(() => _subtitleFont = v) : null,
                    ),
                    const SizedBox(height: 6),
                    _subtitlePreview(context),
                  ],
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _subtitlePreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pos = switch (_subtitlePosition) {
      'Top' => Alignment.topCenter,
      'Center' => Alignment.center,
      _ => Alignment.bottomCenter,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppTheme.surfaceDark, AppTheme.surfaceDarker]),
              ),
            ),
            Align(
              alignment: pos,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _subtitleBg ? Colors.black.withOpacity(0.55) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'This is a subtitle preview.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _subtitleFont,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- Step 4 (matches the HTML template translation UI)
  Widget _stepTranslation(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final targets = const ['Hindi', 'Urdu', 'English'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Translation & Languages', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose source and target languages for your generated shorts.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.graphic_eq, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text('Auto-Detect Source', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Identify spoken language', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65))),
                      ],
                    ),
                  ),
                  Switch.adaptive(value: _autoDetectSource, onChanged: (v) => setState(() => _autoDetectSource = v)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Opacity(
                opacity: _autoDetectSource ? 0.5 : 1,
                child: DropdownButtonFormField<String>(
                  value: _sourceOverride,
                  onChanged: _autoDetectSource ? null : (v) => setState(() => _sourceOverride = v!),
                  items: const [
                    DropdownMenuItem(value: 'English', child: Text('English')),
                    DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
                    DropdownMenuItem(value: 'Urdu', child: Text('Urdu')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Manual override',
                  ),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Target languages', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_targetLangs.length == targets.length) {
                  _targetLangs.clear();
                } else {
                  _targetLangs
                    ..clear()
                    ..addAll(targets);
                }
              }),
              child: const Text('Select all'),
            )
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search languages…',
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          children: [
            for (final lang in targets)
              _langTile(context, lang, selected: _targetLangs.contains(lang), onTap: () {
                setState(() {
                  if (_targetLangs.contains(lang)) {
                    _targetLangs.remove(lang);
                  } else {
                    _targetLangs.add(lang);
                  }
                });
              }),
          ],
        )
      ],
    );
  }

  Widget _langTile(BuildContext context, String lang, {required bool selected, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    final code = switch (lang) {
      'Hindi' => 'HI',
      'Urdu' => 'UR',
      _ => 'EN',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? cs.primary : cs.outline.withOpacity(0.18)),
          color: selected ? cs.primary.withOpacity(0.14) : cs.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(code, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lang, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  Text('Native', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55))),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(999)),
                child: const Icon(Icons.check, size: 14, color: Colors.black),
              )
          ],
        ),
      ),
    );
  }

  // --- Step 5
  Widget _stepDubbing(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Dubbing (audio replace)', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Replace the original audio with generated voice per language.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _dubAudio,
                onChanged: (v) => setState(() => _dubAudio = v),
                title: const Text('Dub audio (replace original)', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Uses installed voice models (offline)'),
              ),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Opacity(
                opacity: _dubAudio ? 1 : 0.5,
                child: Column(
                  children: [
                    for (final lang in _targetLangs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          value: _voiceByLang[lang] ?? 'Default',
                          items: const [
                            DropdownMenuItem(value: 'Default', child: Text('Default voice')),
                            DropdownMenuItem(value: 'Asha', child: Text('Asha')),
                            DropdownMenuItem(value: 'Zain', child: Text('Zain')),
                            DropdownMenuItem(value: 'Ravi', child: Text('Ravi')),
                          ],
                          onChanged: _dubAudio ? (v) => setState(() => _voiceByLang[lang] = v!) : null,
                          decoration: InputDecoration(labelText: '$lang voice'),
                        ),
                      ),
                    if (_targetLangs.isEmpty)
                      Text('Select target languages in Step 4 to configure voices.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6))),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  // --- Step 6
  Widget _stepBranding(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Branding', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Apply watermark settings to all outputs.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _watermark,
                onChanged: (v) => setState(() => _watermark = v),
                title: const Text('Watermark', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Position and opacity'),
              ),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Opacity(
                opacity: _watermark ? 1 : 0.5,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _wmPos,
                      items: const [
                        DropdownMenuItem(value: 'Top-left', child: Text('Top-left')),
                        DropdownMenuItem(value: 'Top-right', child: Text('Top-right')),
                        DropdownMenuItem(value: 'Bottom-left', child: Text('Bottom-left')),
                        DropdownMenuItem(value: 'Bottom-right', child: Text('Bottom-right')),
                      ],
                      onChanged: _watermark ? (v) => setState(() => _wmPos = v!) : null,
                      decoration: const InputDecoration(labelText: 'Position'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Opacity', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text('${(_wmOpacity * 100).round()}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65))),
                      ],
                    ),
                    Slider(
                      value: _wmOpacity,
                      min: 0.2,
                      max: 1,
                      divisions: 8,
                      onChanged: _watermark ? (v) => setState(() => _wmOpacity = v) : null,
                    ),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  // --- Step 7
  Widget _stepOutput(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Output', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose platform preset and quality.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preset', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in const ['YouTube Shorts', 'TikTok', 'Instagram Reels'])
                    ChoiceChip(
                      selected: _preset == p,
                      label: Text(p),
                      onSelected: (_) => setState(() => _preset = p),
                    )
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text('Quality', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  for (final q in const ['Balanced', 'High', 'Small file'])
                    ChoiceChip(
                      selected: _quality == q,
                      label: Text(q),
                      onSelected: (_) => setState(() => _quality = q),
                    )
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CfGradientBanner(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sd_storage, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Storage & models', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      'Estimated temp storage: ~1.4GB\nRequired models: Whisper + Phi-3 (offline)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}
