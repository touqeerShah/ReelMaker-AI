# ClipForge Flutter UI (ReelMaker-AI) — Setup & Run Guide

This README covers the **final setup** after recent changes:
- Flutter Web + Android testing (without Android Studio)
- Minimal Android SDK install on macOS (M1/M2)
- Required exports/imports for shared widgets (e.g., `CfButton`)
- File picking on Web (no `.path`)
- Secrets hygiene (avoid GitHub push blocks)

---

## 0) Prerequisites

### Flutter
- Flutter **stable** installed (you’re on `3.38.8` ✅)

Check:
```bash
flutter --version
flutter doctor
Homebrew (macOS)
brew --version
1) Install Dependencies (macOS, no Android Studio)
A) Android command-line tools + Java
brew install --cask android-commandlinetools
brew install --cask temurin
brew install android-platform-tools
temurin installs Java which sdkmanager needs.

B) Create Android SDK folder and point environment variables
mkdir -p "$HOME/Library/Android/sdk"

echo 'export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk' >> ~/.zshrc
echo 'export ANDROID_HOME=$HOME/Library/Android/sdk' >> ~/.zshrc
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator' >> ~/.zshrc
source ~/.zshrc
C) Install cmdline-tools into your SDK root
This makes Flutter happy (Flutter checks inside $ANDROID_SDK_ROOT):

sdkmanager --sdk_root="$HOME/Library/Android/sdk" "cmdline-tools;latest"
D) Install Android SDK Platform + Build Tools required by Flutter
Flutter now requires API 36 + legacy build tools check:

sdkmanager --sdk_root="$HOME/Library/Android/sdk" --update

sdkmanager --sdk_root="$HOME/Library/Android/sdk" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "build-tools;28.0.3"
E) Accept licenses & configure Flutter
flutter config --android-sdk "$HOME/Library/Android/sdk"
flutter doctor --android-licenses
flutter doctor
Expected: Android toolchain ✅

2) Project Install
From repo root:

flutter pub get
3) Running the App
A) Run on Web (Chrome)
flutter run -d chrome
Hot reload:

press r in terminal

press R for hot restart

B) Run on Android phone (USB)
1) Enable developer mode on phone
Settings → About phone → tap Build number 7x

Settings → Developer options → enable USB debugging

2) Connect phone & verify
adb devices
flutter devices
If unauthorized:

adb kill-server
adb start-server
adb devices
Accept the prompt on the phone.

3) Run
flutter run -d <deviceId>
(or just flutter run if only one device)

4) Web File Picker Fix (IMPORTANT)
On Web: PlatformFile.path is unavailable and may throw.
Use bytes on web and path on mobile/desktop.

Recommended state shape
PlatformFile? selectedVideoFile;
String? selectedVideoPath;      // non-web only
Uint8List? selectedVideoBytes;  // web only
Recommended pick code
final result = await FilePicker.platform.pickFiles(
  type: FileType.video,
  allowMultiple: false,
  withData: kIsWeb,
);

if (result == null || result.files.isEmpty) return;
final file = result.files.single;

setState(() {
  selectedVideoFile = file;
  if (kIsWeb) {
    selectedVideoBytes = file.bytes;
    selectedVideoPath = null;
  } else {
    selectedVideoPath = file.path;
    selectedVideoBytes = null;
  }
});
For large videos on web, prefer withReadStream: kIsWeb and upload via readStream.

5) Shared Widgets (CfButton / CfCard / CfAppBar)
If you use a barrel export file like:

lib/widgets/widgets.dart

Make sure it exports the button widget file:

export 'cf_app_bar.dart';
export 'cf_card.dart';
export 'cf_button.dart'; // required
Also avoid duplicate imports like:

package:clipforge/widgets/widgets.dart

../widgets/widgets.dart

Keep one consistent style (prefer relative inside lib, or package imports everywhere).

6) Secrets & Git Push Protection (Google OAuth)
Do NOT commit OAuth client secrets (GitHub will block pushes).
Move secrets into environment variables / CI secrets.

Recommended approach
Keep placeholders in tracked files:

client_secret = "" or REPLACE_ME

Store real secrets in:

.env (ignored) or your deployment secret store

Add to .gitignore:

.env
.env.*
If a secret was committed locally, you must rewrite local history before pushing:

git fetch origin
git reset --soft origin/main
# remove secrets from files
git add .
git commit -m "Remove secrets from config"
git push origin main
Also rotate the OAuth secret in Google Cloud.

7) Export / Build Outputs
Android APK (release)
flutter build apk --release
APK path:

build/app/outputs/flutter-apk/app-release.apk
Install to connected device:

adb install -r build/app/outputs/flutter-apk/app-release.apk
Web build
flutter build web
Output:

build/web/
8) Troubleshooting
Flutter can’t find SDK
echo $ANDROID_SDK_ROOT
ls "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
flutter config --android-sdk "$ANDROID_SDK_ROOT"
flutter doctor -v
ADB device not detected
use a data-capable cable

unlock phone

set USB mode to File Transfer (MTP)

adb kill-server
adb start-server
adb devices
9) Notes
Xcode/CocoaPods warnings affect iOS/macOS builds only.

Android testing works without Xcode.


If you want, paste your current repo structure for `lib/widgets/` and I’ll tailor the **“Shared Widgets”** section to the exact filenames you have (so it’s copy-paste accurate).
::contentReference[oaicite:0]{index=0}