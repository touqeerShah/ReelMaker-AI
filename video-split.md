Is “everything local on phone” the right approach?

Yes—if your goal is privacy + no uploads. Typical approach:

Video stays on phone (app sandbox or gallery).

Backend stores only: project record, settings, job states, progress logs, outputs list (filenames), timestamps, errors.

To implement on-device FFmpeg in Flutter, note:

FFmpegKit is retired (no more official releases).

A maintained community fork exists as a Flutter package (e.g., ffmpeg_kit_flutter_new).

Flutter’s background processing is isolate-based; for persistent work you typically use WorkManager on Android / BG tasks on iOS, but iOS is more restrictive.

High-level architecture
1) App flow (Flutter)

User picks video locally (gallery/file picker).

User sets:

chunk length (e.g., 30s, 60s)

watermark image + position

channel name text

random flip (on/off)

(optional) output resolution/bitrate

App creates a Project record in backend (metadata only).

App generates Jobs locally: one per chunk.

A local queue runner processes jobs sequentially (concurrency = 1).

2) Storage model

On phone

Input video path/URI (not uploaded)

Output clips in app folder (e.g., .../projects/{id}/clips/)

Local DB (SQLite/Hive) for job queue and status

Backend

Project metadata

Job list + progress + settings used

Output manifests (filenames, durations, timestamps) — not files

Job queue: process one chunk at a time
Local DB schema (example)

projects(id, userId, sourceUri, createdAt, settingsJson)

jobs(id, projectId, startSec, durSec, status, progress, outputPath, error, createdAt)

job_events(id, jobId, ts, message) (optional logs)

Queue runner behavior

Only one active job at a time:

pick next PENDING

set RUNNING

run FFmpeg command

set DONE or FAILED

If app restarts, queue continues from DB.

Background constraints

Android: Foreground service recommended for long video jobs (WorkManager can work, but real-time FFmpeg + app-kill behavior can be tricky).

iOS: long-running background processing is limited; you may require the app to stay in foreground or use BGProcessingTask with constraints.

Flutter background overview + WorkManager notes:

FFmpeg pipeline per chunk (local, original audio preserved)

For each chunk:

Decide:

start time ss

duration t (user chunk size)

random text location (x,y)

random flip (none / hflip / vflip)

Run one FFmpeg command that:

trims the chunk

overlays watermark

draws channel name

optionally flips video

keeps original audio (re-encode audio to AAC for compatibility)

Example FFmpeg command template

(You generate x,y randomly in Dart and inject them.)

ffmpeg -y -hide_banner -loglevel error \
  -ss {START} -t {DUR} -i "input.mp4" \
  -i "watermark.png" \
  -filter_complex "
    [0:v]{FLIP}scale=1280:-2:flags=lanczos[v0];
    [v0][1:v]overlay={WM_X}:{WM_Y}[v1];
    [v1]drawtext=text='{CHANNEL}':x={TXT_X}:y={TXT_Y}:fontsize=28:fontcolor=white:borderw=2[v]
  " \
  -map "[v]" -map 0:a:0? \
  -c:v libx264 -preset veryfast -crf 20 \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "out_chunk_0001.mp4"


Where:

{FLIP} is either empty, hflip, or vflip,

{TXT_X},{TXT_Y} are random positions within “safe margins”

0:a:0? makes audio optional (won’t crash if no audio track)

Watermark: keep it semi-transparent by using PNG with alpha or add format=rgba,colorchannelmixer=aa=0.6 before overlay.

“Change audio frequency a bit to change identity”

I can’t provide steps/commands intended to change identity/fingerprint of audio.

What I can recommend (safe, legit):

loudness normalization (loudnorm)

mild compression (acompressor)

denoise (light)

EQ for clarity (highpass/lowpass)

Example “quality” audio filter (not identity evasion):

-af "loudnorm=I=-16:TP=-1.5:LRA=11"

Step-by-step implementation plan (practical)
Step 1 — On-device FFmpeg integration

Use a maintained Flutter FFmpeg binding (community fork) such as ffmpeg_kit_flutter_new.

If you need full control, build your own FFmpeg binaries + platform channels (more work but future-proof).

Step 2 — Local queue + isolate worker

Persist jobs to SQLite/Hive.

A single worker isolate pops jobs and executes FFmpeg commands.

Update progress (FFmpeg stats callbacks if supported by your FFmpeg binding).

Step 3 — Background mode

Android: foreground service for reliability.

iOS: either keep app in foreground during rendering or use BGProcessingTask (limited).

Flutter background guidance:

Step 4 — Backend record keeping

When project created: send settings + source metadata (duration, resolution).

When each job starts/ends: send status + timestamps + output metadata.

No files uploaded.

1) Output format: fit-to-9:16 without cropping

Target canvas: 1080×1920 (classic Reels/TikTok).

Core video filter (no crop)

Scale video to fit inside 1080×1920 while preserving aspect ratio

Pad to exactly 1080×1920

FFmpeg filter:

scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2


This guarantees:

no cropping

no distortion

black bars where needed

Optional nicer background (blurred fill)

Instead of black bars, create a blurred background layer:

[0:v]split=2[base][fg];
[base]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:1[bg];
[fg]scale=1080:1920:force_original_aspect_ratio=decrease[fg2];
[bg][fg2]overlay=(W-w)/2:(H-h)/2


That still doesn’t “crop the main video”; it crops only the background layer.

2) Per-chunk processing (queue, one at a time)

For each chunk job (start_sec, duration_sec), run one FFmpeg command that:

trims

fits to 9:16

adds watermark (app logo)

adds channel text at random position

(optional) random flip

keeps original audio (re-encode to AAC)

Command template (black bars, simplest)
ffmpeg -y -hide_banner -loglevel error \
  -ss {START} -t {DUR} -i "{IN}" \
  -i "{WATERMARK_PNG}" \
  -filter_complex "
    [0:v]{FLIP}scale=1080:1920:force_original_aspect_ratio=decrease,
         pad=1080:1920:(ow-iw)/2:(oh-ih)/2,
         format=yuv420p[v0];
    [1:v]scale={WM_W}:-1,format=rgba,colorchannelmixer=aa={WM_ALPHA}[wm];
    [v0][wm]overlay={WM_X}:{WM_Y}[v1];
    [v1]drawtext=text='{CHANNEL}':x={TXT_X}:y={TXT_Y}:
        fontsize=36:fontcolor=white:borderw=3:bordercolor=black@0.6[v]
  " \
  -map "[v]" -map 0:a:0? \
  -c:v libx264 -preset veryfast -crf 20 \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "{OUT}"


Where:

{FLIP} is either empty or hflip, or vflip,

{WM_X},{WM_Y} fixed or random (e.g., bottom-right margin)

{TXT_X},{TXT_Y} random safe area positions

{WM_ALPHA} e.g. 0.55

{WM_W} e.g. 180

3) Random placement logic (safe area)

You must randomize within bounds so text doesn’t go off-screen.

Use fixed canvas 1080×1920. Define safe margins:

marginX = 60

marginY = 120 (avoid bottom UI area)

Compute random text position:

x in [60, 1080-60-approxTextWidth]

y in [120, 1920-200] (keep away from bottom)

Practical approach: keep x random but clamp hard, and keep y random in top/middle ranges to avoid UI overlays:

y in [200, 1400]

4) Android local-only storage + backend job records
Local storage (recommended)

Copy selected input video into app storage (so you always have permission):

getApplicationDocumentsDirectory()/projects/{projectId}/input.mp4

Output clips:

.../projects/{projectId}/clips/clip_0001.mp4

Backend storage

Store only:

project settings

each job: chunk index, start, duration, output filename, status, timestamps
No file upload.

5) Queue processing (one at a time) on Android

Implementation pattern:

SQLite/Hive table for jobs (PENDING/RUNNING/DONE/FAILED)

A single worker “runner”:

fetch next pending

run FFmpeg

mark done

repeat

For reliability:

Use a foreground service while rendering, otherwise Android can kill you under load.

6) Chunking the video by length user provides

If user gives chunk length L seconds:

total duration T from ffprobe

chunks: [0..L), [L..2L), ... until T

For each chunk:

create job with start=i*L, dur=min(L, T-start)

7) Answering your specific “don’t crop”

You can keep all content by:

scale=...:force_original_aspect_ratio=decrease

pad=1080:1920:(ow-iw)/2:(oh-ih)/2

This is the correct “fit to reel screen” approach.
watermark position: fixed (bottom-right) or random?