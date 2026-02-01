import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/app_theme.dart';
import '../widgets/widgets.dart'; // keep ONE widgets.dart import

class CreateShortsWizard extends StatefulWidget {
  const CreateShortsWizard({super.key, this.initialCategory});
  
  final String? initialCategory; // 'split' or 'summary'

  @override
  State<CreateShortsWizard> createState() => _CreateShortsWizardState();
}

class _CreateShortsWizardState extends State<CreateShortsWizard> {
  final PageController _controller = PageController();
  int _step = 0;

  // Step 1: Video Selection
  // String? _selectedVideoPath;
  PlatformFile? _selectedVideoFile;
  String? _selectedVideoPath;   // non-web
  Uint8List? _selectedVideoBytes; // web

  // Step 2: Category & Processing Mode
  String _category = 'split'; // 'split' or 'summary'
  String _processingMode = 'split_only'; 
  // Modes: split_only, split_voice, split_translate, ai_best_scenes, ai_summary_hybrid, ai_story_only
  
  // Split settings (always shown)
  int _segmentSeconds = 60;
  int _subscribeSeconds = 5;
  String _watermarkPosition = 'Top-right';
  // Channel name moved to Settings page
  
  // Voice settings (for split_voice mode)
  String _voiceStyle = 'Natural';
  double _voiceSpeed = 1.0;
  
  // Translation settings (for split_translate mode)
  String _targetLanguage = 'Spanish';
  
  // AI mode settings (for all AI summarization modes)
  String _aiLanguage = 'English';
  String _aiVoice = 'Natural Female';
  bool _keepOriginalAudio = false;
  
  // Step 4: Export/Share
  bool _exportLocal = true;
  final Map<String, bool> _socialMediaTargets = {
    'youtube': false,
    'instagram': false,
    'tiktok': false,
    'facebook': false,
  };

  @override
  void initState() {
    super.initState();
    // Set initial category if provided from home page
    if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
      // Set default mode for category
      if (_category == 'summary') {
        _processingMode = 'ai_best_scenes';
      } else {
        _processingMode = 'split_only';
      }
    }
  }

  static const _steps = <String>[
    'Select video',
    'Processing & Settings',
    'Review',
    'Export/Share',
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
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outline.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                for (int i = 0; i < _steps.length; i++) ...[
                  if (i > 0) Expanded(child: Container(height: 2, color: i <= _step ? AppTheme.primary : cs.outline.withOpacity(0.3))),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: i <= _step ? AppTheme.primary : cs.surface,
                      border: Border.all(color: i <= _step ? AppTheme.primary : cs.outline.withOpacity(0.3), width: 2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: i < _step
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : Text('${i + 1}', style: TextStyle(color: i == _step ? Colors.white : cs.onSurface.withOpacity(0.5), fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepSelectVideo(context),
                _stepProcessingAndSettings(context),
                _stepReview(context),
                _stepExportShare(context),
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
    final canProceed = _canProceed();

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
              child: CfButton(
                onPressed: canProceed ? (isLast ? _finish : _next) : null,
                child: Text(isLast ? 'Start Processing' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _selectedVideoFile != null;
      case 1:
        return true; // No validation needed for settings
      case 2:
        return true; // Review always allows proceed
      case 3:
        return _exportLocal || _socialMediaTargets.values.any((v) => v);
      default:
        return false;
    }
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      _controller.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _controller.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _finish() {
    // Navigate to Queue page with project name
    final projectName = 'Short_${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).pop(); // Close wizard
    // TODO: Add project to queue
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "$projectName" to queue')),
    );
  }

  // --- Step 1: Select Video ---
  Widget _stepSelectVideo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          _category == 'summary' 
            ? 'Select video for AI Summary' 
            : 'Select video to Split',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          _category == 'summary'
            ? 'Choose a video to create AI-powered summaries and highlights'
            : 'Choose a video to split into shorts with watermarks',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65)),
        ),
        const SizedBox(height: 16),
        
        if (_selectedVideoPath != null)
          CfCard(
            child: ListTile(
              leading: const Icon(Icons.movie, size: 32),
              title: Text(
                _selectedVideoFile!.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),

              subtitle: const Text('Selected video'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedVideoFile = null;
                  _selectedVideoPath = null;
                  _selectedVideoBytes = null;
                }),
              ),
            ),
          )
        else
          CfCard(
            child: InkWell(
              onTap: () async {
                try {
                    final result = await FilePicker.platform.pickFiles(
                        type: FileType.video,
                        allowMultiple: false,
                        withData: kIsWeb, // ✅ ensures bytes are available on web
                      );

                      if (result == null || result.files.isEmpty) return;

                      final file = result.files.single;

                      setState(() {
                        _selectedVideoFile = file;

                        if (kIsWeb) {
                          _selectedVideoBytes = file.bytes; // ✅ web: use bytes
                          _selectedVideoPath = null;        // ✅ no path on web
                        } else {
                          _selectedVideoPath = file.path;   // ✅ mobile/desktop: use path
                          _selectedVideoBytes = null;
                        }
                      });
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error selecting video: $e')),
                    );
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(48.0),
                child: Column(
                  children: [
                    Icon(Icons.video_library, size: 64, color: cs.primary),
                    const SizedBox(height: 16),
                    Text('Tap to select video', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
                  ],
                ),
              ),
            ),
          ),
            
        const SizedBox(height: 24),
        
        // Show selected video on THIS page (Step 1)
        if (_selectedVideoFile != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECTED VIDEO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedVideoFile!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedVideoFile = null;
                      _selectedVideoPath = null;
                      _selectedVideoBytes = null;
                    });
                  },
                  tooltip: 'Remove and select different video',
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Step 2: Processing Mode + Settings ---
  Widget _stepProcessingAndSettings(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Show selected video
        if (_selectedVideoFile != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.movie, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Video',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        _selectedVideoFile!.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        
        // Category Selection
        Text('What do you want to create?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.category),
            hintText: 'Select category',
            filled: true,
            fillColor: cs.surfaceVariant.withOpacity(0.3),
          ),
          items: const [
            DropdownMenuItem(
              value: 'split',
              child: Row(
                children: [
                  Icon(Icons.content_cut, size: 20),
                  SizedBox(width: 12),
                  Text('Split Videos', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'summary',
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: Colors.purple),
                  SizedBox(width: 12),
                  Text('Create AI Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _category = v;
                // Reset mode to first option of selected category
                if (v == 'split') {
                  _processingMode = 'split_only';
                } else {
                  _processingMode = 'ai_best_scenes';
                }
              });
            }
          },
        ),
        
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),
        
        // Processing Mode Section
        Text('Processing Mode', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        
        // Show Split modes ONLY when category is 'split'
        if (_category == 'split') ...[
          _ProcessingModeCard(
            title: 'Split Only',
            description: 'Split video into segments with watermark',
            icon: Icons.content_cut,
            selected: _processingMode == 'split_only',
            onTap: () => setState(() => _processingMode = 'split_only'),
          ),
          const SizedBox(height: 12),
          
          _ProcessingModeCard(
            title: 'Split + Change Voice',
            description: 'Split and replace audio with TTS',
            icon: Icons.record_voice_over,
            selected: _processingMode == 'split_voice',
            onTap: () => setState(() => _processingMode = 'split_voice'),
          ),
          const SizedBox(height: 12),
          
          _ProcessingModeCard(
            title: 'Split + Translate',
            description: 'Split and translate to another language',
            icon: Icons.translate,
            selected: _processingMode == 'split_translate',
            onTap: () => setState(() => _processingMode = 'split_translate'),
          ),
        ],
        
        // Show Summary modes ONLY when category is 'summary'
        if (_category == 'summary') ...[
          _ProcessingModeCard(
            title: 'AI Best Scenes Only',
            description: 'LLM finds best scenes and creates one highlight video',
            icon: Icons.auto_awesome,
            selected: _processingMode == 'ai_best_scenes',
            onTap: () => setState(() => _processingMode = 'ai_best_scenes'),
            footnote: '⚠️ Requires audio in video',
          ),
          const SizedBox(height: 12),
          
          _ProcessingModeCard(
            title: 'AI Summary + Original Audio',
            description: 'Best scenes with original audio/music + AI voiceover',
            icon: Icons.surround_sound,
            selected: _processingMode == 'ai_summary_hybrid',
            onTap: () => setState(() => _processingMode = 'ai_summary_hybrid'),
            footnote: '⚠️ Requires audio in video',
          ),
          const SizedBox(height: 12),
          
          _ProcessingModeCard(
            title: 'AI Story Only',
            description: 'Selected scenes with AI-generated narration audio',
            icon: Icons.mic,
            selected: _processingMode == 'ai_story_only',
            onTap: () => setState(() => _processingMode = 'ai_story_only'),
            footnote: '⚠️ Requires audio in video',
          ),
        ],
        
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),
        
        // Split Settings (Always shown)
        Text('Split Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        
        Text('Segment Duration', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _segmentSeconds.toDouble(),
                min: 30, max: 120, divisions: 9,
                activeColor: AppTheme.primary,
                label: '$_segmentSeconds sec',
                onChanged: (v) => setState(() => _segmentSeconds = v.toInt()),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Text('$_segmentSeconds sec', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        Text('Subscribe Overlay Duration', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
       Text('Overlay appears in the last N seconds of each segment', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _subscribeSeconds.toDouble(),
                min: 3, max: 10, divisions: 7,
                activeColor: AppTheme.primary,
                label: 'Last $_subscribeSeconds sec',
                onChanged: (v) => setState(() => _subscribeSeconds = v.toInt()),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Text('$_subscribeSeconds sec', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        
        const SizedBox(height: 28),
        
        Text('App Watermark', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outline.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.branding_watermark, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your app logo will appear throughout the video (always enabled)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Logo Position', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _watermarkPosition,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.place),
            hintText: 'Select logo position',
          ),
          items: const [
            DropdownMenuItem(value: 'Top-left', child: Text('Top-left')),
            DropdownMenuItem(value: 'Top-right', child: Text('Top-right')),
            DropdownMenuItem(value: 'Bottom-left', child: Text('Bottom-left')),
            DropdownMenuItem(value: 'Bottom-right', child: Text('Bottom-right')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _watermarkPosition = v);
          },
        ),
        
        // Conditional: Voice Settings (Split + Voice mode)
        if (_processingMode == 'split_voice') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          
          Text('Voice Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          
          Text('Voice Style', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _voiceStyle,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.voice_chat),
              hintText: 'Select voice style',
            ),
            items: const [
              DropdownMenuItem(value: 'Natural', child: Text('Natural')),
              DropdownMenuItem(value: 'Professional', child: Text('Professional')),
              DropdownMenuItem(value: 'Conversational', child: Text('Conversational')),
              DropdownMenuItem(value: 'Energetic', child: Text('Energetic')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _voiceStyle = v);
            },
          ),
          
          const SizedBox(height: 20),
          
          Text('Speech Speed', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _voiceSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  activeColor: AppTheme.primary,
                  label: '${_voiceSpeed.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(() => _voiceSpeed = v),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Text('${_voiceSpeed.toStringAsFixed(1)}x', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
        ],
        
        // Conditional: Translation Settings (Split + Translate mode)
        if (_processingMode == 'split_translate') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          
          Text('Translation Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          
          Text('Target Language', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _targetLanguage,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.language),
              hintText: 'Select target language',
            ),
            items: const [
              DropdownMenuItem(value: 'Spanish', child: Text('Spanish')),
              DropdownMenuItem(value: 'French', child: Text('French')),
              DropdownMenuItem(value: 'German', child: Text('German')),
              DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
              DropdownMenuItem(value: 'Arabic', child: Text('Arabic')),
              DropdownMenuItem(value: 'Chinese', child: Text('Chinese')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _targetLanguage = v);
            },
          ),
          
          const SizedBox(height: 20),
          
          SwitchListTile(
            title: const Text('Keep Original Audio'),
            subtitle: const Text('Play translated subtitles with original audio track'),
            value: _keepOriginalAudio,
            onChanged: (v) => setState(() => _keepOriginalAudio = v),
          ),
        ],
        
        // Conditional: AI Mode Settings (All 3 AI modes)
        if (_processingMode == 'ai_best_scenes' || 
            _processingMode == 'ai_summary_hybrid' || 
            _processingMode == 'ai_story_only') ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          
          Text('AI Summary Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          
          Text('Output Language', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _aiLanguage,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.language),
              hintText: 'Select language for AI summary',
            ),
            items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'Spanish', child: Text('Spanish')),
              DropdownMenuItem(value: 'French', child: Text('French')),
              DropdownMenuItem(value: 'German', child: Text('German')),
              DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
              DropdownMenuItem(value: 'Arabic', child: Text('Arabic')),
              DropdownMenuItem(value: 'Chinese', child: Text('Chinese')),
              DropdownMenuItem(value: 'Portuguese', child: Text('Portuguese')),
              DropdownMenuItem(value: 'Japanese', child: Text('Japanese')),
              DropdownMenuItem(value: 'Korean', child: Text('Korean')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _aiLanguage = v);
            },
          ),
          
          const SizedBox(height: 20),
          
          Text('AI Voice', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _aiVoice,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.record_voice_over),
              hintText: 'Select AI voice',
            ),
            items: const [
              DropdownMenuItem(value: 'Natural Female', child: Text('Natural Female')),
              DropdownMenuItem(value: 'Natural Male', child: Text('Natural Male')),
              DropdownMenuItem(value: 'Professional Female', child: Text('Professional Female')),
              DropdownMenuItem(value: 'Professional Male', child: Text('Professional Male')),
              DropdownMenuItem(value: 'Energetic Female', child: Text('Energetic Female')),
              DropdownMenuItem(value: 'Energetic Male', child: Text('Energetic Male')),
              DropdownMenuItem(value: 'Calm Female', child: Text('Calm Female')),
              DropdownMenuItem(value: 'Calm Male', child: Text('Calm Male')),
              DropdownMenuItem(value: 'Documentary Narrator', child: Text('Documentary Narrator')),
              DropdownMenuItem(value: 'News Anchor', child: Text('News Anchor')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _aiVoice = v);
            },
          ),
          
          // Mode-specific info boxes
          const SizedBox(height: 20),
          if (_processingMode == 'ai_best_scenes')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI analyzes video and extracts best scenes with original audio',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
          if (_processingMode == 'ai_summary_hybrid')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Summary mixes original audio/music with AI storytelling',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
          if (_processingMode == 'ai_story_only')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI generates complete story narration with selected scenes',
                      style: TextStyle(fontSize: 13, color: Colors.purple[700]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  // --- Step 3: Review ---
  Widget _stepReview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    String modeName = _processingMode == 'split_only' 
        ? 'Split Only' 
        : _processingMode == 'split_voice' 
            ? 'Split + Change Voice'
            : _processingMode == 'split_translate'
                ? 'Split + Translate'
                : _processingMode == 'ai_best_scenes'
                    ? 'AI Best Scenes Only'
                    : _processingMode == 'ai_summary_hybrid'
                        ? 'AI Summary + Original Audio'
                        : 'AI Story Only';
    
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Review Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Review your configuration before exporting', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 24),
        
        CfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewItem(label: 'Video', value: _selectedVideoFile?.name ?? 'None'),
              const Divider(),
              _ReviewItem(label: 'Processing Mode', value: modeName),
              const Divider(),
              _ReviewItem(label: 'Segment Duration', value: '$_segmentSeconds seconds'),
              const Divider(),
              _ReviewItem(label: 'Subscribe Overlay', value: 'Last $_subscribeSeconds seconds'),
              const Divider(),
              _ReviewItem(label: 'Watermark Position', value: _watermarkPosition),
              if (_processingMode == 'split_voice') ...[
                const Divider(),
                _ReviewItem(label: 'Voice Style', value: _voiceStyle),
                const Divider(),
_ReviewItem(label: 'Speech Speed', value: '${_voiceSpeed.toStringAsFixed(1)}x'),
              ],
              if (_processingMode == 'split_translate') ...[
                const Divider(),
                _ReviewItem(label: 'Target Language', value: _targetLanguage),
                const Divider(),
                _ReviewItem(label: 'Keep Original Audio', value: _keepOriginalAudio ? 'Yes' : 'No'),
              ],
              if (_processingMode == 'ai_best_scenes' ||
                  _processingMode == 'ai_summary_hybrid' ||
                  _processingMode == 'ai_story_only') ...[
                const Divider(),
                _ReviewItem(label: 'AI Language', value: _aiLanguage),
                const Divider(),
                _ReviewItem(label: 'AI Voice', value: _aiVoice),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 4: Export/Share ---
  Widget _stepExportShare(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Export & Share', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Choose how to export your shorts', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65))),
        const SizedBox(height: 24),
        
        CheckboxListTile(
          title: const Text('Save Locally', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Save to your device'),
          secondary: const Icon(Icons.folder),
          value: _exportLocal,
          onChanged: (v) => setState(() => _exportLocal = v ?? true),
        ),
        
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        
        Text('Push to Social Media', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('Connect and share directly (requires OAuth)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 16),
        
        CheckboxListTile(
          title: const Text('YouTube Shorts'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.play_circle_outline),
          value: _socialMediaTargets['youtube']!,
          enabled: false,
          onChanged: (v) => setState(() => _socialMediaTargets['youtube'] = v ?? false),
        ),
        
        CheckboxListTile(
          title: const Text('Instagram Reels'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.camera_alt),
          value: _socialMediaTargets['instagram']!,
          enabled: false,
          onChanged: (v) => setState(() => _socialMediaTargets['instagram'] = v ?? false),
        ),
        
        CheckboxListTile(
          title: const Text('TikTok'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.music_note),
          value: _socialMediaTargets['tiktok']!,
          enabled: false,
          onChanged: (v) => setState(() => _socialMediaTargets['tiktok'] = v ?? false),
        ),
        
        CheckboxListTile(
          title: const Text('Facebook Reels'),
          subtitle: const Text('Not connected'),
          secondary: const Icon(Icons.facebook),
          value: _socialMediaTargets['facebook']!,
          enabled: false,
          onChanged: (v) => setState(() => _socialMediaTargets['facebook'] = v ?? false),
        ),
        
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Social media connection coming soon!')),
            );
          },
          icon: const Icon(Icons.add_link),
          label: const Text('Connect More Accounts'),
        ),
      ],
    );
  }

  // Helper widget for processing mode cards
  Widget _ProcessingModeCard({
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    String? footnote, // Optional footnote for warnings
  }) {
    return CfCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: selected ? Colors.white : Colors.grey[600], size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(description, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle, color: AppTheme.primary, size: 28),
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    footnote,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for review items
  Widget _ReviewItem({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
