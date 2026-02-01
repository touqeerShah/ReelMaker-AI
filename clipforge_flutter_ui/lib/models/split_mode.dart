/// Split processing mode options
enum SplitMode {
  /// Just split video into segments with watermark and subscribe overlay
  splitOnly,
  
  /// Split video and replace audio with TTS dubbing
  splitVoice,
  
  /// Split video, translate subtitles, and optionally dub to target language
  splitTranslate,
}

extension SplitModeExtension on SplitMode {
  String get value {
    switch (this) {
      case SplitMode.splitOnly:
        return 'split_only';
      case SplitMode.splitVoice:
        return 'split_voice';
      case SplitMode.splitTranslate:
        return 'split_translate';
    }
  }
  
  static SplitMode fromString(String value) {
    switch (value) {
      case 'split_only':
        return SplitMode.splitOnly;
      case 'split_voice':
        return SplitMode.splitVoice;
      case 'split_translate':
        return SplitMode.splitTranslate;
      default:
        return SplitMode.splitOnly;
    }
  }
}
