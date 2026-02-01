# Video Split Feature - Phase 2 Native Implementation Guide

## Completed Components

### ✅ Dart Service Layer
- [`VideoSplitService`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/lib/services/video_split_service.dart) - Service with MethodChannel/EventChannel
- [`SplitMode`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/lib/models/split_mode.dart) - Enum for processing modes
- [`ExportProgress`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/lib/models/export_progress.dart) - Progress tracking model

### ✅ Native Plugin Skeleton
- [`MainActivity.kt`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/android/app/src/main/kotlin/com/example/clipforge/MainActivity.kt) - Android MethodChannel setup
- [`VideoSplitHandler.kt`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/android/app/src/main/kotlin/com/example/clipforge/VideoSplitHandler.kt) - Android handler skeleton
- [`VideoSplitPlugin.swift`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/ios/Runner/VideoSplitPlugin.swift) - iOS plugin skeleton

## Native Implementation Tasks

### Android (Media3 Transformer)

#### 1. Add Dependencies

Add to `android/app/build.gradle.kts`:

```kotlin
dependencies {
    // Media3 for video processing
    implementation("androidx.media3:media3-transformer:1.2.0")
    implementation("androidx.media3:media3-effect:1.2.0")
    implementation("androidx.media3:media3-common:1.2.0")
    
    // Coroutines (already added)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

#### 2. Implement VideoSplitHandler

Replace TODO sections in `VideoSplitHandler.kt`:

**Key implementation points:**
- Use `Transformer` class from Media3
- Configure `EditedMediaItem` with:
  - Time range for segment extraction
  - `ScaleAndRotateTransformation` for aspect-fit to 9:16
  - `OverlayEffect` for watermark (bitmap)
  - `OverlayEffect` for subscribe overlay (time-gated)
- Export to H.264/AAC (1080x1920, 9000k video, 160k audio)

**Aspect-fit scaling math:**
```kotlin
val targetWidth = 1080f
val targetHeight = 1920f
val srcAspect = srcWidth / srcHeight
val targetAspect = targetWidth / targetHeight

val scale = if (srcAspect > targetAspect) {
    targetWidth / srcWidth  // fit to width, pillarbox on sides
} else {
    targetHeight / srcHeight  // fit to height, letterbox top/bottom
}

val scaledWidth = srcWidth * scale
val scaledHeight = srcHeight * scale
val tx = (targetWidth - scaledWidth) / 2
val ty = (targetHeight - scaledHeight) / 2
```

**Watermark overlay:**
- Load watermark bitmap from assets/drawable
- Position based on `watermarkPosition` argument
- Always visible throughout segment

**Subscribe overlay:**
- Create text overlay with channel name + subscribe CTA
- Calculate time threshold: `segmentDuration - subscribeSeconds`
- Use `OverlayEffect` with time range

#### 3. Add Foreground Service

For long exports (>30s), use ForegroundService:
- Create `VideoExportService` extending Service
- Show notification with progress
- Update notification via EventChannel progress

### iOS (AVFoundation)

#### 1. Register Plugin

Update `ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register video split plugin
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    VideoSplitPlugin.register(with: registrar(forPlugin: "VideoSplitPlugin")!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

#### 2. Implement VideoSplitPlugin

Replace TODO sections in `VideoSplitPlugin.swift`:

**Key implementation points:**
- Use `AVMutableComposition` to extract time range
- Create `AVMutableVideoComposition` with:
  - `renderSize`: 1080×1920
  - `layerInstructions` with transform for aspect-fit
- Create `AVMutableVideoCompositionLayerInstruction` for transforms
- Create CALayer hierarchy for overlays:
  - Parent layer at 1080×1920
  - Video sublayer (transformed)
  - Watermark sublayer (always visible)
  - Subscribe sublayer (animated opacity)
- Export with `AVAssetExportSession`

**Aspect-fit transform:**
```swift
let targetSize = CGSize(width: 1080, height: 1920)
let videoTrack = // ... load video track
let naturalSize = videoTrack.naturalSize

let scaleX = targetSize.width / naturalSize.width
let scaleY = targetSize.height / naturalSize.height
let scale = min(scaleX, scaleY)

let scaledWidth = naturalSize.width * scale
let scaledHeight = naturalSize.height * scale
let tx = (targetSize.width - scaledWidth) / 2
let ty = (targetSize.height - scaledHeight) / 2

var transform = CGAffineTransform(scaleX: scale, y: scale)
transform = transform.translatedBy(x: tx / scale, y: ty / scale)
```

**Subscribe overlay animation:**
```swift
let subscribeLayer = CATextLayer()
// ... configure layer ...

let fadeAnimation = CABasicAnimation(keyPath: "opacity")
fadeAnimation.fromValue = 0.0
fadeAnimation.toValue = 1.0
fadeAnimation.duration = 0.3
fadeAnimation.beginTime = segmentDuration - subscribeSeconds
fadeAnimation.fillMode = .forwards
subscribeLayer.add(fadeAnimation, forKey: "fadeIn")
```

## Integration with Wizard

Update [`create_shorts_wizard.dart`](file:///Users/touqeershah/Documents/PharmaTraceProject-Files/ReelMaker-AI/clipforge_flutter_ui/lib/screens/create_shorts_wizard.dart):

```dart
import '../services/video_split_service.dart';
import '../models/split_mode.dart';
import '../models/export_progress.dart';

// In state class:
final _videoSplitService = VideoSplitService();
StreamSubscription<ExportProgress>? _progressSubscription;

// On export button:
Future<void> _startExport() async {
  _progressSubscription = _videoSplitService.progressStream.listen((progress) {
    setState(() {
      // Update UI with progress
    });
  });

  try {
    final outputPaths = await _videoSplitService.splitAndExport(
      inputPath: _selectedVideos.first,
      mode: SplitModeExtension.fromString(_processingMode),
      segmentSeconds: _segmentSeconds,
      subscribeSeconds: _subscribeSeconds,
      watermarkPosition: _watermarkPosition,
      channelName: _channelName,
      outputDir: '/path/to/output',
    );
    
    // Show results
  } catch (e) {
    // Show error
  }
}
```

## Testing Steps

1. **Test progress streaming**: Verify EventChannel updates UI
2. **Test cancellation**: Ensure `cancelExport()` works
3. **Test aspect ratios**: Try 16:9, 4:3, 1:1, 9:16 source videos
4. **Verify aspect-fit**: No cropping, letterbox/pillarbox as expected
5. **Test  overlays**: Watermark positioning, subscribe timing
6. **Test long videos**: ForegroundService (Android), background task (iOS)

## Production Considerations

### Performance
- Use hardware acceleration (MediaCodec on Android, VideoToolbox on iOS)
- Consider quality presets (fast, balanced, high quality)
- Limit concurrent exports to avoid memory pressure

### Storage
- Clean up temp files after export
- Implement caching strategy for segments
- Monitor available disk space before export

### Error Handling
- Handle corrupted videos gracefully
- Retry failed exports with exponential backoff
- Show user-friendly error messages

### Permissions
- Request storage permissions (Android)
- Handle scoped storage (Android 10+)
- Request photo library access (iOS)

## Status

- ✅ Dart service layer complete
- ✅ Plugin skeleton complete
- ⏳ Media3/AVFoundation implementation (requires native coding)
- ⏳ Wizard integration
- ⏳ Progress UI
- ⏳ Results preview
