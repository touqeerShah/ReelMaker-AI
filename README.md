# ReelMaker-AI 🎬

> An AI-powered video processing platform that transforms your videos with intelligent editing, multilingual subtitles, and automated content summarization.


## 📋 Table of Contents

  - [Simple Video Processing](#simple-video-processing)
  - [AI Summary Pipeline](#ai-summary-pipeline)


## 🎯 Overview

**ReelMaker-AI** is a video processing platform designed to automate video editing workflows:

### Use Cases


## ✅ Key Scripts You Want

You requested these scripts (clean separation, minimal overlap):

### 1) Best Scenes Reel (Original Audio + Subtitles)
**Goal:** take the best scenes from a video, keep **original audio**, overlay **original subtitles**, and merge into **one** final video.

**Output:** `best_scenes_original_audio_subs.mp4`


### 2) Summary Reel (Scenes + Original Audio/Subs + Summary Narration)
**Goal:** select some scenes, keep **original audio**, keep **subtitle overlay**, and also add **summary audio narration** (TTS) aligned to the reel.

**Output:** `summary_reel_original_audio_subs_plus_summary_audio.mp4`


### 3) Summary-Only (Summary Audio + Subtitles)
**Goal:** generate a video that contains **only summary narration audio** and **summary subtitles** (no original audio), optionally with a background video/template.

**Output:** `summary_only_audio_subs.mp4`


### 4) Split + Reels from Best Scenes
**Goal:** split/segment the video and produce short “reels” from best scenes.

**Output:** `reels/clip_001.mp4`, `reels/clip_002.mp4`, ...


## 🔄 Workflows

### Simple Video Processing

1. Video Upload  
2. (Optional) Video Splitting  
3. Subtitle Generation  
4. Translation (one or many languages)  
5. Subtitle Overlay  
6. Export

**Supported Languages:** English, Spanish, French, German, Italian, Portuguese, Arabic, Hindi, Mandarin, Japanese, Korean, and more.


### AI Summary Pipeline

1. **Audio Extraction**
2. **Speech-to-Text Transcription** (timestamps + speakers if needed)
3. **Summarization** (key points + chapters)
4. **Scene Matching** (summary points → timestamps)
5. **Clip Generation**
6. **Text-to-Speech** (summary narration)
7. **Compilation** (merge clips + audio + subtitles)

Config options:


## 🛠️ Technology Stack

**Video:** FFmpeg, OpenCV  
**Audio:** Librosa, PyDub  
**ML:** PyTorch, TensorFlow  
**ASR:** Whisper, Google Speech-to-Text  
**Summarization:** OpenAI GPT, BERT, T5  
**TTS:** ElevenLabs, Google TTS, Azure TTS  

Backend:


## 🚀 Getting Started

### Prerequisites

### Installation

```bash
git clone https://github.com/your-username/ReelMaker-AI.git
cd ReelMaker-AI
```

#### Python

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Node.js

```bash
npm install
# or
yarn install
```

#### Environment

```bash
cp .env.example .env
# Edit .env with API keys and configuration values
```

#### Database

```bash
createdb reelmaker_ai
# Run migrations (pick your stack)
python manage.py migrate
# or
npm run migrate
```

#### Run services (example)

```bash
# Start Redis
redis-server

# Start worker (if using Celery)
celery -A app worker --loglevel=info

# Start the app
python app.py
# or
npm run dev
```

## Running Locally (recommended)

These steps cover the most common local development flows: running the local Node backend, the Flutter UI, and a lightweight web demo.


```bash
cd reelmaker-backend
npm install
cp .env.example .env
# edit .env to configure PORT, STORAGE_PROVIDER, DB URL, API keys
npm run dev
# or
npm start

# Quick endpoint test (from repo root)
./reelmaker-backend/test-endpoints.sh
```


```bash
cd clipforge_flutter_ui
flutter pub get
# run on a connected device or simulator
flutter devices
flutter run -d <deviceId>
```


You can open `index.html` in a browser for a static demo, or serve it locally:

```bash
# from repo root
python -m http.server 8000
# then open http://localhost:8000/index.html
# or use a node static server
npx http-server -c-1 .
```



```bash
brew install ffmpeg
```

If you need FFmpeg with subtitle libraries (ass/harfbuzz), install dependencies then build:

```bash
brew install libass freetype fribidi harfbuzz
brew reinstall ffmpeg --build-from-source
```

📱 Android Phone Setup on macOS (M1 Pro) Without Android Studio
1) Install ADB (Android platform-tools)
brew install android-platform-tools
adb version
2) Install Android SDK Command-line Tools (via Homebrew)
brew install --cask android-commandlinetools
3) Fix SDK symlink (IMPORTANT: correct Homebrew path)
Homebrew tools typically live here:

/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager
Create SDK folder + remove wrong link (if any):

mkdir -p "$HOME/Library/Android/sdk/cmdline-tools"
rm -rf "$HOME/Library/Android/sdk/cmdline-tools/latest"
Symlink to correct location:

ln -s "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest" \
  "$HOME/Library/Android/sdk/cmdline-tools/latest"
Verify:

ls -l "$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager"
4) Set environment variables
echo 'export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk' >> ~/.zshrc
echo 'export PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools' >> ~/.zshrc
source ~/.zshrc
Confirm:

which sdkmanager
sdkmanager --version
5) Install minimal Android packages (API 33 example)
sdkmanager --licenses

sdkmanager \
  "platform-tools" \
  "platforms;android-33" \
  "build-tools;33.0.2"
6) Point Flutter to the SDK + accept licenses
flutter config --android-sdk "$HOME/Library/Android/sdk"
flutter doctor --android-licenses
flutter doctor
7) Enable USB debugging on the phone
On Android:

Settings → About phone → tap Build number 7 times

Settings → Developer options → enable:

USB debugging

(Optional) Install via USB

(Optional) USB debugging (Security settings)

8) Connect via USB + authorize
Plug phone in and accept the “Allow USB debugging?” prompt.

Verify:

adb devices
flutter devices
flutter run -d <deviceId>
Quick SDK existence check
ls "$HOME/Library/Android" || echo "Android SDK not found yet"
🎞️ FFmpeg Subtitle Support (libass)
Install dependencies:

brew install libass freetype fribidi harfbuzz
brew reinstall ffmpeg --build-from-source
Verify subtitle filters:

ffmpeg -filters | grep -E 'subtitles|ass'
📁 Project Structure
ReelMaker-AI/
├── src/
│   ├── core/
│   │   ├── video_processor.py
│   │   ├── subtitle_generator.py
│   │   ├── translator.py
│   │   └── audio_extractor.py
│   ├── ai/
│   │   ├── speech_to_text.py
│   │   ├── summarizer.py
│   │   ├── text_to_speech.py
│   │   └── clip_generator.py
│   ├── pipeline/
│   │   ├── simple_pipeline.py
│   │   └── summary_pipeline.py
│   ├── api/
│   │   ├── routes.py
│   │   ├── controllers.py
│   │   └── middleware.py
│   └── utils/
│       ├── config.py
│       ├── storage.py
│       └── validators.py
├── tests/
├── frontend/
├── scripts/
├── docker/
├── docs/
├── .env.example
├── requirements.txt
├── package.json
└── README.md