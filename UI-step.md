1) Master UI Prompt (full app design)

Prompt:

Design a modern Android-first mobile app UI called ClipForge (placeholder name) for offline, on-device video processing. The app turns long videos into Shorts/Reels and can also create a summarized highlight video. The UI must feel professional, fast, and creator-friendly.

Core principles

Mobile-first, touch-friendly, minimal steps.

Local-only processing: clearly indicate “On-device” and show storage usage.

Provide strong job progress visibility (queued → processing → completed → failed).

Clean typography, high contrast, accessible.

Use a sleek dark mode and light mode. Default: dark.

Style: modern creator tools (CapCut/YouTube Studio vibe), but simpler.

Main navigation (bottom tabs)

Home

Projects

Queue

Settings

Home screen

Two large primary cards:

Create Shorts (Shorts Factory)

Create Summary Video (Highlights)

Recent projects list (last 5)

“Import Video” floating action button

Create Shorts flow (wizard)

Step 1: Select video(s) from device storage (multi-select)
Step 2: Choose split method:

Fixed: 30s / 45s / 60s

Smart: “Use Summary Evidence” (optional toggle)
Step 3: Subtitles:

Toggle “Generate subtitles”

Subtitle style picker (font size, background, position)
Step 4: Translation & Languages:

Direction auto-detect with override:

English → Hindi, Urdu

Hindi/Urdu → English

Select target languages (multi-select)
Step 5: Dubbing (Audio Replace):

Toggle “Dub audio (replace original)”

Voice picker per language (if available)
Step 6: Branding:

Watermark toggle + position + opacity
Step 7: Output:

Presets: YouTube Shorts / TikTok / Instagram Reels

Quality selector (Balanced / High / Small file)
Step 8: Start processing

Show estimated storage usage and offline model requirement

Create Summary Video flow

Step 1: Select video
Step 2: Target length: 10 / 15 / 20 minutes
Step 3: Summary style:

Bullet summary / Chapter summary / Story summary
Step 4: Output language: English / Hindi / Urdu
Step 5: Narration:

Toggle “Generate narration audio (replace original audio)”

Voice picker
Step 6: Start processing

Projects screen

Project cards showing:

title, duration, created date, status

outputs: shorts count, languages generated

Tap into a Project detail page:

Timeline view of clips with thumbnails

subtitles preview

translated variants

dub variants

export/share options

Queue screen (critical)

List of jobs with:

progress bar, stage label (Extracting audio / Transcribing / Translating / Dubbing / Rendering)

pause/resume/cancel buttons

warnings: “Device hot”, “Low battery”

Job detail view:

logs in a clean format (not too technical)

per-step completion ticks

retry controls

Settings

Local-only banner: “All processing runs on your device.”

Model management:

Download/Remove models (Whisper model sizes; Phi-3 model)

storage usage meter

Processing constraints:

“Only process while charging”

“Only on Wi-Fi” (for model downloads only)

“Max 1–2 videos per batch”

Language defaults

Watermark defaults

Accessibility controls

Visual style

Color: deep charcoal background, accent color teal or violet (one accent).

Components: rounded cards, soft shadows, clear icons.

Use video thumbnails heavily.

Include empty states, loading skeletons, and error states.

Deliver: a complete mobile UI design with screens, components, and interactions described above, including light/dark variants.

2) Prompt for a Single “Hero” Home Screen (marketing-quality)

Prompt:

Create a polished dark-mode Home screen for an offline video creator app. Two main cards: “Create Shorts” and “Create Summary Video”. Each card shows an icon, short description, and a “Start” button. Below, a “Recent Projects” list with thumbnail previews and status chips (Completed, Processing). Top bar includes app name + storage indicator (“On-device: 5.2GB used”) and a small “Models” badge. Clean, modern creator-tool look with rounded corners and subtle gradients.

3) Prompt for Queue Screen (the most important utility screen)

Prompt:

Design a Queue screen for an offline processing app. Display job cards stacked vertically. Each job card includes: video thumbnail, title, current stage label (e.g., “Transcribing”), progress bar, elapsed time, and quick actions: Pause, Cancel. Add a “Details” chevron. Include a segmented filter: All / Running / Completed / Failed. Provide a compact “Device status” banner at top (Battery %, Temperature warning). Make it clean and readable.

4) Prompt for “Create Shorts” Wizard UI

Prompt:

Design a multi-step wizard for creating shorts from a long video. Use a stepper at the top (1–7). Steps include: Select Video, Split Method (30/45/60 + Smart), Subtitles toggle with style preview, Translation with language direction and multi-select targets, Dub Audio (replace original) with voice picker per language, Watermark settings, Output presets (YouTube Shorts/TikTok/IG Reels) + quality. Bottom sticky bar: Back / Next, final step shows “Start Processing” plus storage and model requirements.

5) Prompt for Project Detail Screen (clip timeline + variants)

Prompt:

Design a Project Detail screen for a processed video. Show a header with video title, original duration, status, and export button. Main area: horizontal timeline of generated clips with thumbnails and timestamps. Each clip expands to show variants: EN subtitles, HI dub, UR dub, different platform presets. Include preview player at top with quick switcher for language variant. Provide actions: “Re-render”, “Delete output”, “Export/Share”.

6) Prompt for Settings + Model Manager

Prompt:

Design Settings for an offline AI video app. Include a section “Models” with cards for Whisper (tiny/base/small) and Phi-3 summarizer. Each card shows size, installed status, download/remove buttons, and a storage bar. Add processing constraints toggles: only while charging, pause on low battery, limit concurrent jobs. Add default languages (English/Hindi/Urdu) and watermark defaults. Keep remembering: all processing runs locally, no cloud upload.