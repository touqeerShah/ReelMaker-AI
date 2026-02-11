
# ReelMaker-AI

Below is the complete, integrated “Shorts Factory” plan that includes:

auto audio extraction

audio → subtitles (once)

“Claude-style” summary that returns time-linked evidence

smart split based on those time ranges (or fixed split if you want)

per-clip subtitles

translation English ⇄ Hindi/Urdu (offline)

dubbed audio (full replace) per language

automated batch runs + upload to YouTube + TikTok + Instagram

1) Core pipeline (single source of truth = transcript timestamps)
A. Ingest (video → metadata)

ffprobe read duration, fps, rotation, audio stream info

Save MediaAsset record in local DB

B. Extract audio early (video → WAV)

ffmpeg extract audio to mono 16kHz WAV

This is what Whisper needs; everything AI runs on audio/text, not video.

C. Transcribe once (WAV → timestamped transcript)

whisper.cpp produces:

segments[]: {start, end, text}

optional word timestamps (nice-to-have)

This transcript is reused for:

subtitles for any clip

smart splitting

summaries with evidence ranges

translation inputs

D. Detect source language and choose direction (English ⇄ Hindi/Urdu)

Run on-device language ID on the transcript:

If it’s mostly en → translate to hi/ur

If it’s mostly hi/ur → translate to en

ML Kit language identification supports Urdu (ur) among many others.

2) “Claude-style” summary WITH time references (your key requirement)

You want the summary to say what it summarized and from which parts/timecodes so you can later cut shorts from those exact times.

How to do it

Chunk transcript into time blocks (recommended):

5–20 min video: chunks of 1–2 minutes

1–2 hour video: chunks of 3–5 minutes

For each chunk, produce JSON like:

{
  "points":[
    {"point":"...", "evidence":[{"start":312.2,"end":368.4}]}
  ]
}


Merge chunk summaries → final summary + “chapters” timeline.

Output (stored in DB):

summary_points[] each with evidence_ranges[]

chapters[] with {start,end,title}

This is what enables smart split.

3) Auto split: fixed split OR smart split (based on evidence)
Option 1: Fixed split (fast, simple)

Generate segments of 30–60s but snap cut points to transcript boundaries (avoid cutting mid-sentence):

find nearest whisper segment boundary around target time

Option 2: Smart split (what you described)

Build clips directly from summary evidence ranges:

for each evidence range, expand to clean boundaries (±1–2s)

enforce clip duration rules (e.g., 20–60s)

deduplicate overlaps and keep top-N best clips

Result: clips contain the “meaningful moments” that the summary referenced.

4) Subtitles per clip (generated separately, without re-running Whisper)

You said: “once video split each part subtitle generate separately”.

Do it like this:
11) For each clip window [clipStart, clipEnd]:

filter global transcript segments that overlap this time window

rebase timestamps so clip starts at 0.0

output clip.srt

✅ This is fast and correct.
❌ Don’t re-transcribe per clip (too slow).

5) Translation (offline) for English ⇄ Hindi/Urdu
Best MVP: ML Kit on-device translation

Translate subtitle text using ML Kit translation, which supports English (en), Hindi (hi), Urdu (ur).

You can produce:

clip_en.srt

clip_hi.srt

clip_ur.srt

6) Full audio replace (dub) per language variant

You want: “generate new short with original video with that new translated audio” — i.e., video stays, audio is replaced.

Dubbing approach that works on-device (MVP)

For each clip + target language:

Take the translated subtitles (or translated transcript segments)

Generate TTS audio per segment (small phrases), not one giant paragraph

Place each TTS segment at its intended timestamp

Duration alignment (critical)

Translations often become longer/shorter than original timing. You need alignment rules:

Per segment alignment strategy

Desired duration = segment.end - segment.start

Generate TTS audio for that segment

If TTS audio is longer than desired:

time-compress slightly (FFmpeg atempo, e.g. 1.05–1.20)

If shorter:

pad silence to fill the slot

Then concatenate segment-audio into one continuous clip track.

Mux: replace original clip audio with the dubbed track:

ffmpeg -i clip.mp4 -i dubbed.wav -map 0:v -map 1:a -c:v copy -c:a aac out.mp4

Note on voice availability: system TTS voices for Urdu/Hindi vary by device/engine; your app must check availability at runtime and allow downloading voices or falling back to subtitles-only if a voice isn’t installed.

7) Handling 5–20 min vs 1–2 hours (performance plan)
For 5–20 minutes

Full pipeline is fine on-device:

extract → transcribe → split → render

Summaries are quick (few chunks)

For 1–2 hours

You must be “chunk-first” and resumable:

process audio + transcription in chunks (3–5 min windows)

persist partial transcript in DB

only render clips after you’ve built the clip list (fixed or evidence-based)

process 1–2 source videos per scheduled run (your batch rule)

This avoids thermal shutdown and RAM blowups.

8) Automation + uploading (YouTube + TikTok + Instagram)
Reality check (important)

Android: you can schedule and run long jobs reliably with WorkManager/foreground execution.

iOS: background processing is not guaranteed for long renders → to make “automation” truly reliable across iOS + Android you need a small backend for publishing and scheduling.

Recommended production setup (still Flutter app)

Phone does: render + create outputs

Phone uploads finished MP4s to your backend storage

Backend does: publishing to:

YouTube (most straightforward automation)

TikTok (requires product/scopes/flow constraints)

Instagram Reels (publishing flow + limits)

This is the cleanest way to deliver “scheduled autopost” for all three platforms.

9) Step-by-step working build plan (no missing pieces)
Milestone 1 — Shorts creation engine (offline)

Flutter UI (import, preset, watermark)

FFmpeg plugin: split + watermark + export

Local job queue (SQLite)
✅ Output: shorts are generated locally

Milestone 2 — Subtitles (one transcription, many clips)

whisper.cpp transcription (per source video once)

per-clip SRT generation by filtering global transcript

burn-in subtitle option
✅ Output: shorts + subtitles

Milestone 3 — Translation (English ⇄ Hindi/Urdu offline)

ML Kit translation model downloads + caching

generate translated SRT per clip
✅ Output: multi-language subtitle variants
(ML Kit supports en/hi/ur for translation.)

Milestone 4 — Summary with evidence → smart split

summarizer returns summary_points + evidence_ranges

clip generator uses evidence to cut shorts
✅ Output: “summary-driven shorts” like you described

Milestone 5 — Dubbing (full audio replace)

TTS per segment

duration alignment (time-stretch/pad)

mux dubbed audio into clip
✅ Output: Hindi/Urdu/English dubbed versions

Milestone 6 — Automation + publish

Android schedule: process 1–2 videos nightly

upload results to backend

backend publishes to YouTube/TikTok/Instagram
✅ Output: fully automated pipeline

The single most important implementation rule

Transcribe once per source video.
Everything else (summary, splitting, subtitles, translation, dubbing) is derived from that timestamped transcript.


I’m assuming:

Flutter app (Android-first, iOS later)

Heavy work in native C++/FFmpeg + whisper.cpp via platform channels / FFI

One transcript per source video (never re-transcribe per clip)

English ⇄ Hindi/Urdu

Dubbing = full audio replace

1) Local DB schema (SQLite)

Use Drift (Flutter) or plain SQLite. Below is SQL DDL you can copy.

PRAGMA foreign_keys = ON;

-- 1) Source videos imported by user or watched folder
CREATE TABLE media_assets (
  id                TEXT PRIMARY KEY,         -- UUID
  source_path       TEXT NOT NULL,            -- local file path
  display_name      TEXT,
  file_size_bytes   INTEGER,
  duration_ms       INTEGER,
  width             INTEGER,
  height            INTEGER,
  fps_num           INTEGER,
  fps_den           INTEGER,
  rotation          INTEGER DEFAULT 0,
  audio_codec       TEXT,
  video_codec       TEXT,
  created_at_ms     INTEGER NOT NULL,
  status            TEXT NOT NULL DEFAULT 'READY'  -- READY|PROCESSING|DONE|FAILED
);

CREATE INDEX idx_media_assets_created_at ON media_assets(created_at_ms);

-- 2) Transcript (global, per media asset)
CREATE TABLE transcripts (
  id                TEXT PRIMARY KEY,         -- UUID
  media_asset_id    TEXT NOT NULL,
  lang_code         TEXT,                     -- detected: en|hi|ur
  whisper_model     TEXT,                     -- tiny|base|small...
  json_path         TEXT NOT NULL,            -- transcript JSON stored on disk
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_transcripts_media ON transcripts(media_asset_id);

-- 3) Summary with evidence ranges (Claude-style traceability)
CREATE TABLE summaries (
  id                TEXT PRIMARY KEY,         -- UUID
  media_asset_id    TEXT NOT NULL,
  engine            TEXT NOT NULL,            -- local_llm|rules|cloud
  json_path         TEXT NOT NULL,            -- stores points + evidence ranges + chapters
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_summaries_media ON summaries(media_asset_id);

-- 4) Clip plan (time ranges selected for shorts)
CREATE TABLE clips (
  id                TEXT PRIMARY KEY,         -- UUID
  media_asset_id    TEXT NOT NULL,
  start_ms          INTEGER NOT NULL,
  end_ms            INTEGER NOT NULL,
  strategy          TEXT NOT NULL,            -- FIXED|SMART_EVIDENCE|CHAPTER|MANUAL
  score             REAL DEFAULT 0.0,         -- optional ranking
  title_hint        TEXT,                     -- optional
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE
);

CREATE INDEX idx_clips_media ON clips(media_asset_id);

-- 5) Per-clip subtitles (derived from global transcript)
CREATE TABLE subtitles (
  id                TEXT PRIMARY KEY,         -- UUID
  clip_id           TEXT NOT NULL,
  lang_code         TEXT NOT NULL,            -- en|hi|ur
  format            TEXT NOT NULL,            -- srt|vtt
  path              TEXT NOT NULL,
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_subtitles_clip_lang_fmt ON subtitles(clip_id, lang_code, format);

-- 6) Dub audio per clip per language
CREATE TABLE dubs (
  id                TEXT PRIMARY KEY,         -- UUID
  clip_id           TEXT NOT NULL,
  lang_code         TEXT NOT NULL,            -- en|hi|ur
  voice_id          TEXT,                     -- system voice name or piper model id
  wav_path          TEXT NOT NULL,            -- final dubbed wav
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_dubs_clip_lang ON dubs(clip_id, lang_code);

-- 7) Render outputs (final mp4 variants)
CREATE TABLE renders (
  id                TEXT PRIMARY KEY,         -- UUID
  clip_id           TEXT NOT NULL,
  lang_code         TEXT NOT NULL,            -- en|hi|ur
  render_preset     TEXT NOT NULL,            -- YT_SHORTS|TIKTOK|IG_REELS
  mp4_path          TEXT NOT NULL,
  width             INTEGER,
  height            INTEGER,
  bitrate_kbps      INTEGER,
  duration_ms       INTEGER,
  created_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
);

CREATE INDEX idx_renders_clip ON renders(clip_id);

-- 8) Publishing jobs (one render can publish to multiple platforms)
CREATE TABLE publish_jobs (
  id                TEXT PRIMARY KEY,         -- UUID
  render_id         TEXT NOT NULL,
  platform          TEXT NOT NULL,            -- YOUTUBE|TIKTOK|INSTAGRAM
  scheduled_at_ms   INTEGER,                  -- null = post asap
  status            TEXT NOT NULL,            -- QUEUED|UPLOADING|PUBLISHED|FAILED|RETRY_WAIT
  attempts          INTEGER NOT NULL DEFAULT 0,
  last_error        TEXT,
  remote_post_id    TEXT,                     -- returned by platform
  created_at_ms     INTEGER NOT NULL,
  updated_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (render_id) REFERENCES renders(id) ON DELETE CASCADE
);

CREATE INDEX idx_publish_jobs_status ON publish_jobs(status);
CREATE INDEX idx_publish_jobs_schedule ON publish_jobs(scheduled_at_ms);

-- 9) Background processing jobs (the pipeline orchestrator)
CREATE TABLE pipeline_jobs (
  id                TEXT PRIMARY KEY,         -- UUID
  media_asset_id    TEXT NOT NULL,
  kind              TEXT NOT NULL,            -- TRANSCRIBE|SUMMARIZE|CLIP|SUBTITLE|TRANSLATE|DUB|RENDER|UPLOAD|PUBLISH
  payload_json      TEXT NOT NULL,            -- parameters (languages, preset, watermark, etc.)
  status            TEXT NOT NULL,            -- QUEUED|RUNNING|DONE|FAILED|RETRY_WAIT|CANCELLED
  attempts          INTEGER NOT NULL DEFAULT 0,
  last_error        TEXT,
  created_at_ms     INTEGER NOT NULL,
  updated_at_ms     INTEGER NOT NULL,
  FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE
);

CREATE INDEX idx_pipeline_jobs_status ON pipeline_jobs(status);
CREATE INDEX idx_pipeline_jobs_media_kind ON pipeline_jobs(media_asset_id, kind);

On-disk JSON formats you store

transcript.json (whisper segments)

summary.json (points + evidence ranges + chapters)

Optional: clip_plan.json if you want audit/debug.

2) Job state machine (pipeline orchestration)

Use one top-level orchestrator that schedules sub-jobs. Here are the canonical states and transitions.

A) Pipeline job statuses

QUEUED

RUNNING

DONE

RETRY_WAIT (exponential backoff)

FAILED (permanent)

CANCELLED

B) Full pipeline (Option A + dubbing)

For each media_asset_id:

TRANSCRIBE

input: audio.wav

output: transcript.json

(optional) SUMMARIZE

input: transcript

output: summary.json (points + evidence)

CLIP

strategy: FIXED or SMART_EVIDENCE

output: rows in clips

SUBTITLE

per clip: generate clip_en.srt from global transcript

TRANSLATE

per clip: generate clip_hi.srt, clip_ur.srt (or reverse direction)

DUB

per clip per language: generate dub_hi.wav, dub_ur.wav, optionally dub_en.wav

RENDER

per clip per language per preset: output final MP4

UPLOAD

upload to backend storage (recommended)

PUBLISH

backend posts to YouTube/TikTok/Instagram

C) Retry policy (recommended defaults)

For local processing (FFmpeg/Whisper/TTS): retry 1–2 times max (fail fast if device resources are low)

For uploads/publishing: retry 5–8 times with backoff: 1m, 5m, 15m, 1h, 6h…

D) “Batch 1–2 videos per schedule run”

Scheduler selects:

next media_assets with status READY

create one pipeline job per asset

stop after 1–2 assets

3) File layout (simple and debug-friendly)

For each media asset:

/AppData/ShortsFactory/
  assets/{mediaId}/
    source.mp4               (optional copy, or use original path)
    audio_16k_mono.wav
    transcript.json
    summary.json
    clips/{clipId}/
      en.srt
      hi.srt
      ur.srt
      dub_hi.wav
      dub_ur.wav
      renders/
        YT_SHORTS_hi.mp4
        YT_SHORTS_ur.mp4
        IG_REELS_hi.mp4
        ...

4) FFmpeg command templates (copy/paste ready)

Notes:

Replace paths safely (quote them).

Prefer re-encode for accurate cuts (mobile-friendly reliability).

For speed: you can do stream copy, but cuts may be inaccurate if not on keyframes.

4.1 Probe metadata
ffprobe -hide_banner -v error -print_format json -show_format -show_streams "input.mp4"

4.2 Extract audio (16k mono WAV) — for Whisper
ffmpeg -y -i "input.mp4" \
  -vn -ac 1 -ar 16000 -c:a pcm_s16le \
  "audio_16k_mono.wav"

4.3 Cut a clip (accurate) + convert to 9:16 + watermark

Accurate cut (recommended):

ffmpeg -y -ss 120.0 -to 180.0 -i "input.mp4" \
  -vf "scale=-2:1920,crop=1080:1920" \
  -c:v libx264 -preset veryfast -crf 20 \
  -c:a aac -b:a 128k \
  "clip_base.mp4"


Add watermark overlay (PNG with alpha) at top-right:

ffmpeg -y -i "clip_base.mp4" -i "watermark.png" \
  -filter_complex "overlay=W-w-24:24" \
  -c:v libx264 -preset veryfast -crf 20 \
  -c:a copy \
  "clip_watermarked.mp4"


If you need “fit inside” instead of crop (avoid losing edges), use scale + pad instead of crop.

4.4 Burn subtitles into video (optional)
ffmpeg -y -i "clip_watermarked.mp4" \
  -vf "subtitles=clip_en.srt" \
  -c:v libx264 -preset veryfast -crf 20 \
  -c:a copy \
  "clip_subbed.mp4"

4.5 Replace audio with dubbed WAV (full replace)
ffmpeg -y -i "clip_watermarked.mp4" -i "dub_hi.wav" \
  -map 0:v:0 -map 1:a:0 \
  -c:v copy \
  -c:a aac -b:a 160k \
  -shortest \
  "clip_hi_dubbed.mp4"

4.6 Time-stretch audio slightly if it runs long (per segment or whole track)

If your dub is slightly longer than the clip:

speed up audio with atempo (0.5–2.0 per filter; chain if needed)

ffmpeg -y -i "dub_hi.wav" \
  -filter:a "atempo=1.10" \
  "dub_hi_faster.wav"


Then mux dub_hi_faster.wav.

5) Dubbing implementation (segment-aligned TTS without headaches)
Strategy

Use transcript/subtitle segments with [start, end]

Generate TTS audio per segment text

If audio duration > slot: atempo speed up slightly

If shorter: pad silence

Concatenate all segments into one dub.wav

How to create silence blocks with FFmpeg

Create N seconds of silence:

ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1.25 "silence_1p25.wav"

Concatenate WAV files (concat demuxer)

Create concat.txt:

file 'seg000.wav'
file 'silence_0p20.wav'
file 'seg001.wav'
...


Then:

ffmpeg -y -f concat -safe 0 -i concat.txt -c copy "dub_final.wav"


This approach is robust and easy to debug.

6) Rendering presets (YouTube Shorts / TikTok / IG Reels)

You can start with one safe preset:

1080x1920

H.264 + AAC

8–12 Mbps video, 160 kbps audio

Example:

ffmpeg -y -i "input.mp4" \
  -vf "scale=-2:1920,crop=1080:1920" \
  -c:v libx264 -profile:v high -level 4.1 -pix_fmt yuv420p \
  -b:v 9000k -maxrate 9000k -bufsize 18000k \
  -c:a aac -b:a 160k -ar 48000 \
  "out_1080x1920.mp4"

7) What I recommend you implement next (in code)
A) Define your enums (shared across Flutter + native)

PipelineKind

JobStatus

RenderPreset

Platform

LangCode

B) Build a deterministic orchestrator

Pseudologic:

If no transcript → enqueue TRANSCRIBE

If no clips → enqueue CLIP

For each clip:

if no EN subtitles → SUBTITLE

if translation enabled → TRANSLATE

if dubbing enabled → DUB

render variants → RENDER

Upload results → create publish jobs

C) Make every step resumable

All long steps should:

write outputs to disk

then mark DB row as DONE
So if app kills/restarts, it continues.

If you want, I’ll give you the exact JSON schema I recommend for:

transcript.json

summary.json (with points[] + evidence[])

clip_plan output from smart-split

…and a clean job runner loop design for Flutter + Android WorkManager integration (so batches run automatically).
You’re not missing it — you’re describing two distinct user workflows that share the same core building blocks, and the product needs to support both cleanly:

Shorts Factory: Split → subtitle → translate → (optional) dub → export/upload

Summary Builder: Audio → text → summary with evidence → pick parts → render either (a) shorts OR (b) one combined “summary video” with new summary audio (full replace)

Below is the revised architecture and plan that explicitly supports both, without duplicating work.

1) Unify the app around “Pipelines” (two modes, shared components)
Shared core components (used by both modes)

Ingest: ffprobe + asset DB record

Audio extract: ffmpeg → audio_16k_mono.wav

ASR: whisper.cpp → transcript.json with timestamps

Clip cutter: ffmpeg cut based on time ranges

Subtitle generator: derive SRT per clip from global transcript

Translator: translate text (en ⇄ hi/ur)

TTS: generate dubbed audio (full replace) and align duration

Renderer: watermark + optional burn subtitles + mux audio

Two user pipelines
Pipeline A — Shorts Factory

User chooses: “Create Shorts”

Split strategy:

Fixed 30–60s (snap to transcript boundaries), or

Smart from summary evidence (optional)

Per clip:

Subtitles (on/off)

Translate subtitles (on/off)

Dub audio full replace per language (on/off)

Output: multiple shorts, per platform preset, per language

Pipeline B — Summary Builder

User chooses: “Create Summary Video”

Steps:

Transcript (ASR)

Summary (Claude-style) with evidence ranges

Build summary timeline:

either auto-select best ranges to total 10–20 min

or user manually selects parts/chapters

Render:

One combined summary video (concat chosen ranges)

Generate a new summary narration script

Generate new summary audio (TTS full replace)

Replace audio on the combined video (full replace)

Output:

summary_video.mp4 (10–20 min)

optionally also export shorts from those same ranges

This directly matches what you said:

“audio -> text -> summary -> each part -> audio to -> video clip or those clipe combine into summary video just with new summary audio”

2) What changes in your DB schema (add “timelines” and “summary renders”)

You already have clips for shorts. For Summary Builder you need a timeline (a list of ranges) and an output render.

Add tables
-- A timeline is a named ordered list of ranges from a source video
CREATE TABLE timelines (
  id              TEXT PRIMARY KEY,   -- UUID
  media_asset_id  TEXT NOT NULL,
  type            TEXT NOT NULL,       -- SHORTS|SUMMARY
  title           TEXT,
  total_ms        INTEGER DEFAULT 0,
  created_at_ms   INTEGER NOT NULL,
  FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE
);

CREATE TABLE timeline_ranges (
  id            TEXT PRIMARY KEY,     -- UUID
  timeline_id   TEXT NOT NULL,
  ord           INTEGER NOT NULL,      -- order in timeline
  start_ms      INTEGER NOT NULL,
  end_ms        INTEGER NOT NULL,
  source_note   TEXT,                 -- e.g. "summary point #3"
  FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE
);

CREATE INDEX idx_timeline_ranges_timeline ON timeline_ranges(timeline_id, ord);

-- Summary narration assets (script + audio)
CREATE TABLE narrations (
  id            TEXT PRIMARY KEY,
  timeline_id   TEXT NOT NULL,
  lang_code     TEXT NOT NULL,        -- en|hi|ur
  script_path   TEXT NOT NULL,        -- narration script text/json
  wav_path      TEXT NOT NULL,        -- final narration wav
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE
);

-- Render output for a timeline (summary video is one render per language/preset)
CREATE TABLE timeline_renders (
  id            TEXT PRIMARY KEY,
  timeline_id   TEXT NOT NULL,
  lang_code     TEXT NOT NULL,
  render_preset TEXT NOT NULL,
  mp4_path      TEXT NOT NULL,
  duration_ms   INTEGER,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE
);


Now:

Shorts Factory uses clips + renders

Summary Builder uses timelines + timeline_ranges + narrations + timeline_renders

Both still use the same transcript.

3) Revised job kinds (so orchestration covers both)

Add/rename pipeline kinds so the runner can handle both flows:

EXTRACT_AUDIO

TRANSCRIBE

SUMMARIZE (produces evidence ranges)

BUILD_CLIPS_FIXED

BUILD_CLIPS_FROM_EVIDENCE

BUILD_TIMELINE_SUMMARY (choose ranges until total 10–20 min)

SUBTITLE_CLIPS

TRANSLATE_SUBS

DUB_CLIPS

RENDER_CLIPS

GENERATE_NARRATION_SCRIPT (for summary timeline)

TTS_NARRATION

RENDER_TIMELINE_SUMMARY_VIDEO (concat + mux narration audio)

UPLOAD

PUBLISH

4) The two workflows step-by-step (exact)
Workflow A: Split + Subtitles + Translate + (optional) Dub (Shorts Factory)

Ingest video

Extract WAV 16k

Whisper transcript once

Build clips:

fixed 30–60s (snap boundaries)

For each clip:

generate SRT from global transcript

translate SRT to target languages

(optional) create dubbed audio (full replace) from translated SRT

render MP4 variants (per language/preset)

Upload + publish

Workflow B: Summary video (10–20 min) with new summary audio (full replace)

Ingest video

Extract WAV 16k

Whisper transcript once

Summarize transcript → output:

summary points

evidence ranges

chapters

Build summary timeline:

auto-select evidence ranges until total reaches 10–20 min

merge/clean overlaps

snap to sentence boundaries

Create narration script:

either per-range narration, or one continuous narration

TTS narration audio (full replace)

Render summary video:

cut each range

concatenate to single mp4

replace audio with narration wav (full replace)

Optionally also generate shorts from the same ranges

Upload + publish

5) Key implementation detail: “summary audio must match video length”

For summary videos, narration length won’t naturally match the concatenated video.

You have two sane MVP policies:

Policy 1 (recommended MVP): “Video defines length”

Create narration segments aligned per-range:

Range A (45s) → narration for A must fit 45s

if narration too long → mild time-compress TTS audio

if too short → silence padding or slower voice rate (if supported)

Policy 2: “Narration defines length”

Generate narration first, then choose fewer/more ranges to match narration length.

This is harder and less predictable.

Do Policy 1 first. It’s deterministic and debuggable.

6) UI design (so users can choose either mode cleanly)

Home screen:

Create Shorts

Create Summary Video

Create Shorts:

Fixed split duration (30/45/60)

Subtitles on/off

Translate to: Hindi / Urdu / English

Dub audio: off / full replace

Output: YouTube / TikTok / Instagram presets

Schedule batch processing + auto-publish

Create Summary Video:

Target duration: 10 / 15 / 20 min

Summary style: “bullet”, “story”, “chapters”

Output language: English / Hindi / Urdu

Narration: full replace (default)

Optional: also export shorts from summary

7) What to build first (minimal but complete)
Sprint 1 (foundation)

Ingest + ffprobe

Extract WAV

Whisper transcript → transcript.json

Fixed split clips

Render clips (watermark)

Sprint 2 (Shorts Factory MVP)

Generate per-clip SRT from global transcript

Translate SRT (en ⇄ hi/ur)

Render subtitle versions (burn or sidecar)

Sprint 3 (Dubbing MVP)

TTS per segment and align durations

Full replace audio mux

Render dubbed language versions

Sprint 4 (Summary Builder MVP)

Summarize with evidence ranges

Build summary timeline (10–20 min)

Generate narration script + TTS

Render combined summary video with narration audio

If you want, I’ll now provide two concrete JSON schemas you can enforce in code:

summary.json (points + evidence + chapters)

timeline_build.json (selected ranges + narration text per range)

…and a single orchestrator algorithm that runs either pipeline from configuration flags, so you don’t end up with two separate codepaths.

suggest project name

Here are strong project-name options, grouped by style. I’m prioritizing names that fit your product: auto Shorts creation + subtitles/translation + dubbing + summary video builder.

Brandable, short, app-store friendly

ClipForge

ShortSmith

ReelForge

DubCut

ClipPilot

QuickReel

Vidzly

Sniply

Cliply

Reelio

“AI” positioned (clear what it does)

AutoShorts AI

ReelMaker AI

DubReel AI

ClipGen AI

ShortsStudio AI

SubDub AI

Emphasize translation/dubbing

DubBridge

LinguaReel

DubLingo

VoiceSwap Studio (note: “swap” can sound like voice cloning; avoid if you don’t want that association)

TranslateTube (good for YouTube-first)

Emphasize summarization/highlights

HighlightHub

SummaClip

RecapReel

KeyMoment

StoryCut

More “pro tool” vibe

CreatorPipeline

StudioFlow

ContentAssembler

BatchReels Studio

CreatorOps

My top 5 picks (best balance of brand + meaning)

ClipForge (strong, broad, memorable)

ReelForge (very on-point for IG/TikTok)

DubCut (clearly includes dubbing)

RecapReel (speaks to summary + shorts)

ClipPilot (automation “pilot” vibe)

If you tell me whether you want the name to feel more like a creator app (fun) or a pro automation tool (serious), I’ll narrow to 3 and also suggest a tagline + package name (Android) + bundle ID (iOS) format.

what ai model plan to run for make summary 
Thought for 1m 34s

For on-device “make summary”, the best plan is to summarize in English with a small local instruct model, and use offline translation only when needed. This gives you higher quality and keeps the model small/fast on phones.

Recommended model plan (production-practical)
Plan A (my default MVP): Translate ⇄ Summarize with a small English model

Why: Hindi/Urdu summarization quality varies a lot across small models; translating the transcript to English first is usually more reliable.

Models

Summarizer LLM (local): Phi-3 Mini Instruct (3.8B)

Open model, strong for instruction tasks; you can run quantized versions on-device.

Translator (offline): Google ML Kit on-device translation (supports dynamic offline packs).

Flow

Whisper transcript with timestamps (already in your pipeline)

Detect transcript language (en/hi/ur) (ML Kit language ID supports Urdu).

If source is hi/ur → translate transcript to English (ML Kit)

Chunk transcript (1–3 min blocks) + keep each block’s [start,end]

Run Phi-3 Mini to output JSON:

summary_points[]

each point includes evidence_ranges[] with {start,end}

If the user wants the summary in Hindi/Urdu, translate the final summary text back with ML Kit.

This gives you “Claude-style summary with time references” without needing a multilingual LLM.

Plan B (direct multilingual summary): Qwen2.5-3B-Instruct

If you want the LLM itself to summarize directly in Hindi/Urdu without translation:

Qwen2.5-3B-Instruct (multilingual-capable family; 3B is still phone-friendly when quantized).

Use this when:

You want native-language phrasing and fewer translation artifacts,

And you can tolerate a bit more compute than an English-only 2B model.

Plan C (smallest English summarizer): Gemma-2-2B-IT

If you need smaller/faster than Phi-3:

Gemma-2-2B-IT (instruction tuned)

Caveat: it’s largely English-focused, so it pairs best with Plan A (translate → summarize → translate back).

Runtime choice (how you actually run the summary model on phone)
Option 1 (fastest to ship): llama.cpp + GGUF

llama.cpp expects models in GGUF format.

Phi-3 Mini has an official GGUF repo available.

This is the most straightforward way to embed a local summarizer in a Flutter app via a native plugin/FFI.

Option 2 (best mobile performance if you invest): MLC LLM

MLC LLM provides Android/iOS deployment guidance and is built for on-device performance.

This is great long-term, but integration/model packaging can be more work than llama.cpp.

What I’d implement first (clear recommendation)

Start with Plan A:

Phi-3 Mini (GGUF, 4-bit) as the summarizer

ML Kit for offline translation (en ⇄ hi/ur)

Reason: it’s the most reliable path to good summaries across English/Hindi/Urdu while keeping compute reasonable.

Output format you should force (so you can cut clips later)

Always have the model produce JSON like:

{
  "points": [
    {
      "title": "Main idea",
      "summary": "1–2 lines",
      "evidence": [{"start_sec": 312.2, "end_sec": 368.4}]
    }
  ],
  "chapters": [
    {"title": "Intro", "start_sec": 0, "end_sec": 420}
  ]
}


Because your clipper just consumes evidence[] → creates shorts or builds the 10–20 min summary timeline.
For your use case (timestamped transcript → summary + evidence ranges → smart clips, and English ⇄ Hindi/Urdu), the best single choice is:

Pick: Phi-3 Mini 4K Instruct (3.8B) in GGUF, run with llama.cpp

Why this is the best fit

Strong instruction-following for structured outputs (your JSON: points[], evidence[], chapters[]).

Small enough for phones when quantized (4-bit), while still producing coherent summaries.

Official GGUF availability makes integration easier with llama.cpp.

Model + runtime

Model: microsoft/Phi-3-mini-4k-instruct-gguf

Runtime: llama.cpp (GGUF inference)

How to use it in your pipeline (recommended “best quality” flow)
1) Always summarize in English for reliability

If transcript is Hindi/Urdu → translate to English first (offline translation in your app).

Run Phi-3 to produce the structured summary + evidence ranges.

If user wants the summary in Hindi/Urdu, translate the final summary back.

This avoids multilingual edge-cases where small LLMs can get messy, while still supporting English ⇄ Hindi/Urdu cleanly.

Quantization settings I recommend (important)

Avoid ultra-low quantization for summary quality.

Default (best balance): Q4_K_M (4-bit)

If device is strong (8–12GB RAM): Q5_K_M

Avoid: Q2_K for models like Qwen2.5 where users have reported gibberish at very low quants.

Phi-3 GGUF repos typically provide multiple quant files; start with Q4_K_M.

Why not choose Qwen2.5-3B or Gemma-2-2B as “the one”

They’re good, but for your specific requirements:

Qwen2.5-3B-Instruct GGUF exists and is solid, but low quant levels can degrade badly; you’ll spend more time tuning prompts/quant choices.

Gemma-2-2B-IT GGUF is smaller and fast, but Phi-3 usually gives more dependable structured instruction behavior for “emit strict JSON with ranges” tasks.

If you want a fallback model later:

Fallback for weaker phones: Gemma-2-2B-IT (quantized)

What to implement (summary prompt contract)

With Phi-3, enforce a strict schema like:

{
  "points":[
    {"title":"", "summary":"", "evidence":[{"start_sec":0.0,"end_sec":0.0}]}
  ],
  "chapters":[{"title":"", "start_sec":0.0, "end_sec":0.0}]
}


Then your clipper uses evidence[] directly.

Bottom line

Use Phi-3 Mini 4K Instruct (GGUF) + llama.cpp, summarize in English (translate hi/ur → en first), and output JSON with evidence time ranges. That’s the most reliable “one model” plan for your app right now.





TTS (Text-to-Speech): System Default / SherpaTTS

By default, it often relies on the installed Android Text-to-Speech engine (Google TTS or Samsung TTS) to save space.

Pro Tip: For better quality, users (like you) often install SherpaTTS (which runs VITS or Piper models) alongside RTranslator to get that natural, non-robotic voice offline.