import 'package:flutter/material.dart';

import '../widgets/widgets.dart';

class CreateSummaryWizard extends StatefulWidget {
  const CreateSummaryWizard({super.key});

  @override
  State<CreateSummaryWizard> createState() => _CreateSummaryWizardState();
}

class _CreateSummaryWizardState extends State<CreateSummaryWizard> {
  final PageController _controller = PageController();
  int _step = 0;

  String _video = 'Podcast_Ep42_Raw.mp4';
  int _targetMinutes = 15;
  String _summaryStyle = 'Chapter summary';
  String _outputLang = 'English';
  bool _narration = false;
  String _voice = 'Default';

  static const _steps = <String>[
    'Select video',
    'Target length',
    'Summary style',
    'Output language',
    'Narration',
    'Start',
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
        title: const Text('Create Summary Video'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
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
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.onSurface.withOpacity(0.55), fontWeight: FontWeight.w700),
                    )
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
                _s1(context),
                _s2(context),
                _s3(context),
                _s4(context),
                _s5(context),
                _s6(context),
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
                onPressed: isLast ? _start : _next,
                child: Text(isLast ? 'Start processing' : 'Next'),
              ),
            )
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

  void _start() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Queued'),
        content: const Text('UI prototype: summary job would be queued for on-device processing.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Widget _s1(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Select video', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose one video to summarize (UI placeholder).', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            value: _video,
            items: const [
              DropdownMenuItem(value: 'Podcast_Ep42_Raw.mp4', child: Text('Podcast_Ep42_Raw.mp4')),
              DropdownMenuItem(value: 'Workshop_Recording.mp4', child: Text('Workshop_Recording.mp4')),
              DropdownMenuItem(value: 'Vlog_TravelDay1.mov', child: Text('Vlog_TravelDay1.mov')),
            ],
            onChanged: (v) => setState(() => _video = v!),
            decoration: const InputDecoration(labelText: 'Video'),
          ),
        )
      ],
    );
  }

  Widget _s2(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Target length', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Select the desired highlight duration.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            children: [
              for (final m in const [10, 15, 20])
                ChoiceChip(
                  selected: _targetMinutes == m,
                  label: Text('$m minutes'),
                  onSelected: (_) => setState(() => _targetMinutes = m),
                )
            ],
          ),
        )
      ],
    );
  }

  Widget _s3(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Summary style', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('How should the highlight be structured?', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            value: _summaryStyle,
            items: const [
              DropdownMenuItem(value: 'Bullet summary', child: Text('Bullet summary')),
              DropdownMenuItem(value: 'Chapter summary', child: Text('Chapter summary')),
              DropdownMenuItem(value: 'Story summary', child: Text('Story summary')),
            ],
            onChanged: (v) => setState(() => _summaryStyle = v!),
            decoration: const InputDecoration(labelText: 'Style'),
          ),
        )
      ],
    );
  }

  Widget _s4(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Output language', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Select the language for on-screen text and narration.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            value: _outputLang,
            items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
              DropdownMenuItem(value: 'Urdu', child: Text('Urdu')),
            ],
            onChanged: (v) => setState(() => _outputLang = v!),
            decoration: const InputDecoration(labelText: 'Language'),
          ),
        )
      ],
    );
  }

  Widget _s5(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Narration', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Optionally generate narration audio (replace original).', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _narration,
                onChanged: (v) => setState(() => _narration = v),
                title: const Text('Generate narration audio', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Offline TTS voice models'),
              ),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Opacity(
                opacity: _narration ? 1 : 0.5,
                child: DropdownButtonFormField<String>(
                  value: _voice,
                  items: const [
                    DropdownMenuItem(value: 'Default', child: Text('Default')),
                    DropdownMenuItem(value: 'Asha', child: Text('Asha')),
                    DropdownMenuItem(value: 'Ravi', child: Text('Ravi')),
                    DropdownMenuItem(value: 'Zain', child: Text('Zain')),
                  ],
                  onChanged: _narration ? (v) => setState(() => _voice = v!) : null,
                  decoration: const InputDecoration(labelText: 'Voice'),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _s6(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Ready to process', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Review and start on-device processing.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 16),
        CfGradientBanner(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimate', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
              const SizedBox(height: 6),
              Text('Temp storage: ~900MB\nRequired models: Whisper + Phi-3', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text('Output: $_targetMinutes min • $_summaryStyle • $_outputLang', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        )
      ],
    );
  }
}
