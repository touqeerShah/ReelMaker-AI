import 'dart:async';

import 'package:flutter/services.dart';

class LocalWhisperService {
  static const MethodChannel _channel =
      MethodChannel('com.clipforge/local_whisper');
  static const EventChannel _progressChannel =
      EventChannel('com.clipforge/local_whisper/progress');

  Future<String> transcribeAudioToSrt({
    required String audioPath,
    void Function(Map<String, dynamic> progress)? onProgress,
  }) async {
    StreamSubscription? sub;
    if (onProgress != null) {
      sub = _progressChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          onProgress(Map<String, dynamic>.from(event));
        }
      });
    }

    final result = await _channel.invokeMethod<String>(
      'transcribeAudioLocal',
      {'audioPath': audioPath},
    );
    await sub?.cancel();

    if (result == null || result.trim().isEmpty) {
      throw Exception('Local whisper returned empty transcript');
    }
    return result;
  }
}
