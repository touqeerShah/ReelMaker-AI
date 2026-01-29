# ClipForge (UI prototype)

This is a **Flutter UI-only** prototype for ClipForge: an Android-first offline/on-device video processing app.

## Run

```bash
flutter pub get
flutter run
```

## Notes
- UI only (no real file picking / model downloads / processing engine).
- Dark mode is the default; users can switch theme in Settings.


1) Generate Android + iOS (recommended)

From inside your project folder:

cd ~/Downloads/clipforge_flutter_ui
flutter create .


This will create (at minimum): android/, ios/, test/, and other missing scaffolding.

2) Fetch deps and run on Android
flutter pub get
flutter devices
flutter run

3) If you want to run on macOS/web too (optional)

Enable those platforms first, then regenerate:

flutter config --enable-macos-desktop
flutter config --enable-web
flutter create .


Then you can run:

flutter run -d macos
# or
flutter run -d chrome

Notes

flutter create . won’t overwrite your lib/ — it adds missing platform scaffolding and config.

If you plan to publish Android-first, just generating Android is enough.

If you paste the output of flutter doctor, I can tell you what Android Studio/SDK piece (if any) is still missing before flutter run succeeds.