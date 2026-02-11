Below is a backend-only, step-by-step plan to build the app so everything runs locally on the phone (no cloud, no uploads). I’m describing “backend” as the on-device processing engine + job system + local storage, independent of UI.

I’ll structure this as:

Backend architecture (modules + responsibilities)

Step-by-step build order (what to implement first, with deliverables)

Two pipelines supported (Shorts Factory vs Summary Builder)

Key local-only choices for translation + summarization + dubbing

1) On-device backend architecture
A. Core services (Dart)

These are pure Dart modules your UI calls.

LocalStore

owns folder layout, naming, cleanup policies

LocalDB (SQLite)

stores assets, transcripts, clips, subtitles, dubs, renders, pipeline jobs

JobQueue + JobRunner

durable job queue (SQLite-backed)

runs jobs sequentially (or limited parallel) with pause/resume/retry

emits progress events (Stream)

PipelineOrchestrator

builds a DAG of jobs for a given asset + config

ensures “transcribe once” rule

produces either:

many shorts (Pipeline A)

one combined summary video (Pipeline B)

B. Native engines (via Platform Channels / FFI)

These do the heavy lifting.

FFmpeg/FFprobe wrapper

extract audio

cut clips

concat clips

watermark

mux new audio (full replace)

optional burn subtitles

ASR engine: whisper.cpp

input: audio_16k_mono.wav

output: transcript.json with segments {start,end,text}

LLM engine: llama.cpp (Phi-3 Mini GGUF)

summarization + evidence ranges + chapters

optional translation fallback (when you don’t have a dedicated offline translator)

TTS engine

MVP: Android TextToSpeech + iOS AVSpeechSynthesizer

output: per-segment WAV files, concatenated into final dub/narration WAV

2) Step-by-step build plan (backend only)
Step 1 — Create “backend skeleton” in Flutter

Goal: a callable backend API with no media yet.

Deliverables:

LocalStore (folder layout + helper methods)

LocalDB (Drift/SQLite) with tables:

media_assets, transcripts, summaries, clips, subtitles, dubs, renders, pipeline_jobs

JobQueue:

enqueue(job), cancel(job), retry(job)

JobRunner:

runs jobs, updates status, emits progress events as a Stream<JobEvent>

Definition you want early

A single Dart entrypoint:

Future<void> runPipeline(String mediaAssetId, PipelineConfig config);
Stream<JobEvent> jobEvents(String pipelineJobId);

Step 2 — FFmpeg/FFprobe integration (local)

Goal: prove you can run ffprobe + ffmpeg commands locally and store outputs.

Deliverables:

MediaEngine service (Dart API) with native calls:

probe(videoPath) -> MediaMeta

extractAudio(videoPath) -> audioWavPath

cutClip(videoPath, start, end) -> clipMp4Path

concatClips(list<clipPaths>) -> combinedMp4Path

muxAudio(videoPath, wavPath) -> outMp4Path

overlayWatermark(videoPath, watermarkPng) -> outMp4Path

Backend jobs you can now run:

PROBE_MEDIA

EXTRACT_AUDIO

CUT_CLIP

RENDER_CLIP

Deliverable test: import a video, extract audio, cut one 30–60s clip, export MP4.

Step 3 — Whisper (transcribe once)

Goal: create transcript with timestamps once per source.

Deliverables:

AsrEngine (whisper.cpp wrapper):

transcribe(wavPath) -> transcript.json

Transcript format:

segments: {startSec,endSec,text}

Backend jobs:

TRANSCRIBE

Critical rule implemented now

If transcript exists for media_asset_id, do not re-run.

Step 4 — Clip planning engine (Fixed split + Smart split stubs)

Goal: backend can produce clip time ranges without rendering yet.

Deliverables:

ClipPlanner:

fixedSplit(durationSec=60, snapToTranscript=true)

smartSplitFromEvidence(evidenceRanges) (stub for later)

Backend jobs:

BUILD_CLIPS_FIXED

BUILD_CLIPS_FROM_EVIDENCE (stub until Step 7)

Storage

Write clips rows: start_ms, end_ms, strategy.

Step 5 — Subtitle generation per clip (derived from global transcript)

Goal: per-clip SRT without re-transcribing.

Deliverables:

SubtitleEngine (Dart):

loads transcript.json

filters segments overlapping [clipStart, clipEnd]

rebases timestamps (clipStart becomes 0)

writes clip_en.srt

Backend jobs:

SUBTITLE_CLIPS

Now you have: Split + subtitles all local.

Step 6 — Offline translation (English ⇄ Hindi/Urdu) — local-only plan

Because you said no cloud, you need a local translator.

You have two practical options:

Option 6A (recommended for “local-only, predictable”): LLM-based translation (Phi-3)

Use the same Phi-3 Mini engine to translate subtitle text.

Pros: single runtime everywhere (Android+iOS)

Cons: translation quality varies; you must enforce short segments and strict prompts.

Option 6B (Android-only improvement later): ML Kit offline translation

Great on Android, but iOS equivalent offline translation is not as straightforward.

Since you said “focus backend now” and “local-only”, I recommend Option 6A first to keep parity.

Deliverables:

TranslationEngine:

translateSrt(inputSrt, srcLang, dstLang) -> outputSrt

It should translate line-by-line, not whole documents.

Backend jobs:

TRANSLATE_SUBS producing hi.srt, ur.srt, and reverse to en.srt if needed.

Step 7 — Local summarization with evidence (Phi-3 + llama.cpp)

Goal: “Claude-style summary with time references” locally.

Deliverables:

SummarizerEngine:

chunk transcript by time window (1–2 min for short videos; 3–5 min for long)

asks Phi-3 for JSON:

points[] each with evidence:[{startSec,endSec}]

optional chapters[]

Backend jobs:

SUMMARIZE

Stored artifact:

summary.json

Step 8 — Smart splitting from summary evidence

Goal: create meaningful shorts automatically from summary evidence.

Deliverables:

ClipPlanner.smartSplitFromEvidence(summary.json):

collect all evidence ranges

expand to natural boundaries (nearest transcript segment edges)

enforce:

min clip length (e.g., 20s)

max (e.g., 60s)

avoid overlaps

score clips (optional) and pick top N

Backend jobs:

BUILD_CLIPS_FROM_EVIDENCE (now real)

Step 9 — Dubbing (full audio replace) from translated subtitles

Goal: generate dub track per clip and replace audio.

Deliverables:

DubEngine:

for each subtitle segment:

TTS synthesize audio for that segment text

fit into its (end-start) time slot:

if longer: time-compress slightly

if shorter: pad silence

concatenate all segments into dub_{lang}.wav

Backend jobs:

DUB_CLIPS produces dubs for hi/ur/en (as needed)

Then:

RENDER_CLIPS uses ffmpeg to:

cut clip video

mux dub wav as the only audio (full replace)

add watermark

optional burn subtitles

Step 10 — Summary Video pipeline (combine parts + new narration audio)

This is your second workflow: “audio→text→summary→parts→combine into 10–20 min summary video with new summary audio”

Deliverables:

TimelineBuilder:

from summary.json choose ranges until total reaches target (10/15/20 min)

NarrationScriptEngine:

produce narration script aligned per-range (so it fits)

NarrationTtsEngine:

TTS per-range, align duration, concat into narration.wav

SummaryVideoRenderer:

cut each range

concat to one video

mux narration.wav (full replace)

Backend jobs:

BUILD_TIMELINE_SUMMARY

GENERATE_NARRATION_SCRIPT

TTS_NARRATION

RENDER_TIMELINE_SUMMARY_VIDEO

Everything remains local.

3) Two pipelines (exact job chains)
Pipeline A — Shorts Factory (Split + subtitles + translate + dub + render)

Minimal:

PROBE → EXTRACT_AUDIO → TRANSCRIBE → BUILD_CLIPS_FIXED → SUBTITLE_CLIPS → RENDER_CLIPS

Full:

PROBE → EXTRACT_AUDIO → TRANSCRIBE → (SUMMARIZE optional) → BUILD_CLIPS_FIXED or BUILD_CLIPS_FROM_EVIDENCE
→ SUBTITLE_CLIPS → TRANSLATE_SUBS → DUB_CLIPS → RENDER_CLIPS

Pipeline B — Summary Builder (10–20 min combined + narration audio replace)

PROBE → EXTRACT_AUDIO → TRANSCRIBE → SUMMARIZE
→ BUILD_TIMELINE_SUMMARY → GENERATE_NARRATION_SCRIPT → TTS_NARRATION
→ RENDER_TIMELINE_SUMMARY_VIDEO
(Optional) BUILD_CLIPS_FROM_EVIDENCE → render shorts too

4) Important “local-only” engineering notes (so you don’t get stuck)
Translation local-only reality

If you want Android + iOS with no cloud, the most uniform solution is:

Use the LLM (Phi-3) as translator initially.
Later you can add:

Android: ML Kit offline translation as a “fast path”

iOS: keep LLM translation unless you integrate a dedicated offline MT model

Long videos (1–2 hours)

You must make every heavy step chunked and resumable:

ASR chunking or at least incremental transcript writes

summarization in chunks

clip rendering only after clip plan computed

job runner should survive app restart

Background execution

Android: you can do scheduled jobs more reliably.

iOS: don’t assume long background renders will run when app is closed—still local, but you may require the app to be open for long processing.


Below is a backend-only, step-by-step plan to build the app so everything runs locally on the phone (no cloud, no uploads). I’m describing “backend” as the on-device processing engine + job system + local storage, independent of UI.

I’ll structure this as:

Backend architecture (modules + responsibilities)

Step-by-step build order (what to implement first, with deliverables)

Two pipelines supported (Shorts Factory vs Summary Builder)

Key local-only choices for translation + summarization + dubbing

1) On-device backend architecture
A. Core services (Dart)

These are pure Dart modules your UI calls.

LocalStore

owns folder layout, naming, cleanup policies

LocalDB (SQLite)

stores assets, transcripts, clips, subtitles, dubs, renders, pipeline jobs

JobQueue + JobRunner

durable job queue (SQLite-backed)

runs jobs sequentially (or limited parallel) with pause/resume/retry

emits progress events (Stream)

PipelineOrchestrator

builds a DAG of jobs for a given asset + config

ensures “transcribe once” rule

produces either:

many shorts (Pipeline A)

one combined summary video (Pipeline B)

B. Native engines (via Platform Channels / FFI)

These do the heavy lifting.

FFmpeg/FFprobe wrapper

extract audio

cut clips

concat clips

watermark

mux new audio (full replace)

optional burn subtitles

ASR engine: whisper.cpp

input: audio_16k_mono.wav

output: transcript.json with segments {start,end,text}

LLM engine: llama.cpp (Phi-3 Mini GGUF)

summarization + evidence ranges + chapters

optional translation fallback (when you don’t have a dedicated offline translator)

TTS engine

MVP: Android TextToSpeech + iOS AVSpeechSynthesizer

output: per-segment WAV files, concatenated into final dub/narration WAV

2) Step-by-step build plan (backend only)
Step 1 — Create “backend skeleton” in Flutter

Goal: a callable backend API with no media yet.

Deliverables:

LocalStore (folder layout + helper methods)

LocalDB (Drift/SQLite) with tables:

media_assets, transcripts, summaries, clips, subtitles, dubs, renders, pipeline_jobs

JobQueue:

enqueue(job), cancel(job), retry(job)

JobRunner:

runs jobs, updates status, emits progress events as a Stream<JobEvent>

Definition you want early

A single Dart entrypoint:

Future<void> runPipeline(String mediaAssetId, PipelineConfig config);
Stream<JobEvent> jobEvents(String pipelineJobId);

Step 2 — FFmpeg/FFprobe integration (local)

Goal: prove you can run ffprobe + ffmpeg commands locally and store outputs.

Deliverables:

MediaEngine service (Dart API) with native calls:

probe(videoPath) -> MediaMeta

extractAudio(videoPath) -> audioWavPath

cutClip(videoPath, start, end) -> clipMp4Path

concatClips(list<clipPaths>) -> combinedMp4Path

muxAudio(videoPath, wavPath) -> outMp4Path

overlayWatermark(videoPath, watermarkPng) -> outMp4Path

Backend jobs you can now run:

PROBE_MEDIA

EXTRACT_AUDIO

CUT_CLIP

RENDER_CLIP

Deliverable test: import a video, extract audio, cut one 30–60s clip, export MP4.

Step 3 — Whisper (transcribe once)

Goal: create transcript with timestamps once per source.

Deliverables:

AsrEngine (whisper.cpp wrapper):

transcribe(wavPath) -> transcript.json

Transcript format:

segments: {startSec,endSec,text}

Backend jobs:

TRANSCRIBE

Critical rule implemented now

If transcript exists for media_asset_id, do not re-run.

Step 4 — Clip planning engine (Fixed split + Smart split stubs)

Goal: backend can produce clip time ranges without rendering yet.

Deliverables:

ClipPlanner:

fixedSplit(durationSec=60, snapToTranscript=true)

smartSplitFromEvidence(evidenceRanges) (stub for later)

Backend jobs:

BUILD_CLIPS_FIXED

BUILD_CLIPS_FROM_EVIDENCE (stub until Step 7)

Storage

Write clips rows: start_ms, end_ms, strategy.

Step 5 — Subtitle generation per clip (derived from global transcript)

Goal: per-clip SRT without re-transcribing.

Deliverables:

SubtitleEngine (Dart):

loads transcript.json

filters segments overlapping [clipStart, clipEnd]

rebases timestamps (clipStart becomes 0)

writes clip_en.srt

Backend jobs:

SUBTITLE_CLIPS

Now you have: Split + subtitles all local.

Step 6 — Offline translation (English ⇄ Hindi/Urdu) — local-only plan

Because you said no cloud, you need a local translator.

You have two practical options:

Option 6A (recommended for “local-only, predictable”): LLM-based translation (Phi-3)

Use the same Phi-3 Mini engine to translate subtitle text.

Pros: single runtime everywhere (Android+iOS)

Cons: translation quality varies; you must enforce short segments and strict prompts.

Option 6B (Android-only improvement later): ML Kit offline translation

Great on Android, but iOS equivalent offline translation is not as straightforward.

Since you said “focus backend now” and “local-only”, I recommend Option 6A first to keep parity.

Deliverables:

TranslationEngine:

translateSrt(inputSrt, srcLang, dstLang) -> outputSrt

It should translate line-by-line, not whole documents.

Backend jobs:

TRANSLATE_SUBS producing hi.srt, ur.srt, and reverse to en.srt if needed.

Step 7 — Local summarization with evidence (Phi-3 + llama.cpp)

Goal: “Claude-style summary with time references” locally.

Deliverables:

SummarizerEngine:

chunk transcript by time window (1–2 min for short videos; 3–5 min for long)

asks Phi-3 for JSON:

points[] each with evidence:[{startSec,endSec}]

optional chapters[]

Backend jobs:

SUMMARIZE

Stored artifact:

summary.json

Step 8 — Smart splitting from summary evidence

Goal: create meaningful shorts automatically from summary evidence.

Deliverables:

ClipPlanner.smartSplitFromEvidence(summary.json):

collect all evidence ranges

expand to natural boundaries (nearest transcript segment edges)

enforce:

min clip length (e.g., 20s)

max (e.g., 60s)

avoid overlaps

score clips (optional) and pick top N

Backend jobs:

BUILD_CLIPS_FROM_EVIDENCE (now real)

Step 9 — Dubbing (full audio replace) from translated subtitles

Goal: generate dub track per clip and replace audio.

Deliverables:

DubEngine:

for each subtitle segment:

TTS synthesize audio for that segment text

fit into its (end-start) time slot:

if longer: time-compress slightly

if shorter: pad silence

concatenate all segments into dub_{lang}.wav

Backend jobs:

DUB_CLIPS produces dubs for hi/ur/en (as needed)

Then:

RENDER_CLIPS uses ffmpeg to:

cut clip video

mux dub wav as the only audio (full replace)

add watermark

optional burn subtitles

Step 10 — Summary Video pipeline (combine parts + new narration audio)

This is your second workflow: “audio→text→summary→parts→combine into 10–20 min summary video with new summary audio”

Deliverables:

TimelineBuilder:

from summary.json choose ranges until total reaches target (10/15/20 min)

NarrationScriptEngine:

produce narration script aligned per-range (so it fits)

NarrationTtsEngine:

TTS per-range, align duration, concat into narration.wav

SummaryVideoRenderer:

cut each range

concat to one video

mux narration.wav (full replace)

Backend jobs:

BUILD_TIMELINE_SUMMARY

GENERATE_NARRATION_SCRIPT

TTS_NARRATION

RENDER_TIMELINE_SUMMARY_VIDEO

Everything remains local.

3) Two pipelines (exact job chains)
Pipeline A — Shorts Factory (Split + subtitles + translate + dub + render)

Minimal:

PROBE → EXTRACT_AUDIO → TRANSCRIBE → BUILD_CLIPS_FIXED → SUBTITLE_CLIPS → RENDER_CLIPS

Full:

PROBE → EXTRACT_AUDIO → TRANSCRIBE → (SUMMARIZE optional) → BUILD_CLIPS_FIXED or BUILD_CLIPS_FROM_EVIDENCE
→ SUBTITLE_CLIPS → TRANSLATE_SUBS → DUB_CLIPS → RENDER_CLIPS

Pipeline B — Summary Builder (10–20 min combined + narration audio replace)

PROBE → EXTRACT_AUDIO → TRANSCRIBE → SUMMARIZE
→ BUILD_TIMELINE_SUMMARY → GENERATE_NARRATION_SCRIPT → TTS_NARRATION
→ RENDER_TIMELINE_SUMMARY_VIDEO
(Optional) BUILD_CLIPS_FROM_EVIDENCE → render shorts too

4) Important “local-only” engineering notes (so you don’t get stuck)
Translation local-only reality

If you want Android + iOS with no cloud, the most uniform solution is:

Use the LLM (Phi-3) as translator initially.
Later you can add:

Android: ML Kit offline translation as a “fast path”

iOS: keep LLM translation unless you integrate a dedicated offline MT model

Long videos (1–2 hours)

You must make every heavy step chunked and resumable:

ASR chunking or at least incremental transcript writes

summarization in chunks

clip rendering only after clip plan computed

job runner should survive app restart

Background execution

Android: you can do scheduled jobs more reliably.

iOS: don’t assume long background renders will run when app is closed—still local, but you may require the app to be open for long processing.

5) What I need from you to finalize “backend task list”

To write your exact implementation checklist (files/classes/functions), tell me two decisions:

For translation (local-only, both Android+iOS), do you accept Phi-3 translation as MVP? (Recommended for parity)

For summary model runtime, do you prefer:

llama.cpp (GGUF) only (simpler), or

MLC later (more performance work)?

If you don’t want to answer, I’ll assume:

MVP translation = Phi-3

Summary runtime = llama.cpp GGUF (Phi-3 Mini Q4_K_M)

…and I’ll produce a concrete “week-by-week backend build” checklist with module interfaces.

MVP translation = Phi-3

Summary runtime = llama.cpp GGUF (Phi-3 Mini Q4_K_M)

Locked in:

Translation MVP: Phi-3 (same local LLM)

Summarization runtime: llama.cpp + GGUF using Phi-3 Mini Q4_K_M

Everything local on-device (no cloud)

Below is a step-by-step backend implementation plan with module boundaries, file structure, job DAG, prompts, and hard rules so your team can build it without rethinking architecture later.

1) Backend target architecture (on-device)
A. Dart “Backend API” layer (called by UI later)

Goal: UI should only call 2–3 functions.

Public API (Dart)
class LocalBackend {
  Future<String> importVideo(String path); // returns mediaAssetId
  Future<String> startPipeline(String mediaAssetId, PipelineConfig cfg); // returns pipelineJobId
  Stream<JobEvent> watchPipeline(String pipelineJobId);
  Future<void> cancelPipeline(String pipelineJobId);
}

B. Native engines (invoked from Dart via Platform Channels / FFI)

FFmpeg/ffprobe: extract audio, cut/concat, watermark, mux audio, burn subtitles

whisper.cpp: transcript with timestamps (once per source)

llama.cpp: Phi-3 summarization + translation (strict JSON + strict output)

2) Repo / folder structure (backend-first)
/lib/backend/
  local_backend.dart
  pipeline/
    pipeline_config.dart
    pipeline_orchestrator.dart
    job_kinds.dart
    job_runner.dart
    job_queue.dart
    progress.dart
  store/
    local_store.dart
    paths.dart
    cleanup.dart
  db/
    db.dart
    schema.sql
    dao_*.dart
  engines/
    media_engine.dart        // FFmpeg wrapper (Dart)
    asr_engine.dart          // whisper wrapper (Dart)
    llm_engine.dart          // llama.cpp wrapper (Dart)
    tts_engine.dart          // system TTS wrapper (Dart)
  domain/
    transcript.dart          // models
    summary.dart
    clip.dart
    timeline.dart

/android/
  src/main/cpp/
    ffmpeg/...
    whisper.cpp/...
    llama.cpp/...
    bridge/
      media_bridge.cpp
      whisper_bridge.cpp
      llama_bridge.cpp
      audio_utils.cpp

3) SQLite schema (minimum required for MVP)

You already accepted the earlier schema; for your MVP you can start with these tables only:

media_assets

transcripts

summaries

clips

subtitles

dubs

renders

pipeline_jobs

(You can add timelines + timeline_ranges later when you implement “combined summary video”.)

4) Job system (durable, resumable, local)
Core rule

Every step must be resumable:

write output to disk

then mark DB row DONE

if app restarts, runner continues from DB

Job statuses

QUEUED → RUNNING → DONE
Errors: RETRY_WAIT or FAILED
User action: CANCELLED

Concurrency

Default: 1 heavy job at a time (avoid thermal throttling)

Allow small parallelism only for lightweight steps (like generating SRT files)

5) Two pipelines (explicit, no confusion)
Pipeline A — Shorts Factory

User wants: split → subtitles → translate → dub (full replace) → render

Job DAG

PROBE_MEDIA

EXTRACT_AUDIO_16K

TRANSCRIBE_WHISPER

BUILD_CLIPS_FIXED (30–60s, snap to transcript)

GEN_SUBS_EN_PER_CLIP (derive from global transcript)

TRANSLATE_SUBS_PHI3 (en ⇄ hi/ur)

DUB_TTS_FULL_REPLACE (per clip per lang)

RENDER_CLIP_VARIANTS

Pipeline B — Summary Builder

User wants: audio→text→summary with evidence→select parts→combine → new narration audio → summary video

Job DAG

PROBE_MEDIA

EXTRACT_AUDIO_16K

TRANSCRIBE_WHISPER

SUMMARIZE_WITH_EVIDENCE_PHI3 (JSON points + evidence ranges)

BUILD_SUMMARY_TIMELINE (pick ranges to total 10/15/20 min)

GENERATE_NARRATION_SCRIPT_PHI3 (aligned per range)

TTS_NARRATION_FULL_REPLACE

RENDER_SUMMARY_VIDEO (concat ranges + mux narration)

6) Exact module responsibilities
6.1 MediaEngine (FFmpeg)

Dart interface:

abstract class MediaEngine {
  Future<MediaMeta> probe(String videoPath);
  Future<String> extractAudio16kMonoWav(String videoPath, String outWavPath);
  Future<String> cutClipMp4(String videoPath, double startSec, double endSec, String outPath);
  Future<String> concatMp4(List<String> clipPaths, String outPath);
  Future<String> muxAudioReplace(String videoPath, String wavPath, String outPath);
  Future<String> overlayWatermark(String videoPath, String watermarkPng, String outPath);
  Future<String> burnSubtitles(String videoPath, String srtPath, String outPath);
}

6.2 AsrEngine (whisper.cpp)
abstract class AsrEngine {
  Future<String> transcribeToJson(String wavPath, String outJsonPath, {String model = "base"});
}

6.3 LlmEngine (llama.cpp with Phi-3 Mini Q4_K_M)
abstract class LlmEngine {
  Future<String> completeJson({
    required String system,
    required String user,
    required String schemaHint,
    required int maxTokens,
    required double temperature,
  });
}

6.4 TtsEngine (system TTS)
abstract class TtsEngine {
  Future<bool> isLangSupported(String langCode); // en, hi, ur
  Future<String> synthToWav(String text, String langCode, String outWavPath, {String? voiceId});
}

7) Hard “backend rules” (must implement early)

Transcribe once per source
If transcripts row exists → reuse it.

Never re-run whisper per clip
Per-clip subtitles are derived from global transcript by time filtering + rebasing.

Everything is time-ranged
Every summary point must reference evidence ranges {startSec,endSec}.

Full audio replace means
Video audio is always replaced with dub/narration track (no mixing in MVP).

Clip boundaries snap to transcript
Cuts should align to nearest transcript segment boundary to avoid mid-word cuts.

8) Prompts (strict JSON contracts)
8.1 Summarize with evidence (Phi-3)

System

You are a summarization engine. Output MUST be valid JSON only.
Do not include markdown. Do not include comments. Do not include extra keys.


User

I will give you a list of transcript segments with timestamps.
Task:
1) Create 8–20 summary points.
2) For each point, provide evidence ranges referencing the timestamps from the transcript.
Rules:
- evidence ranges must be within provided timestamps
- keep evidence ranges short (5–60 seconds each)
- include 1–3 evidence ranges per point
- output JSON with keys: points, chapters

Transcript segments:
<SEGMENTS_JSON>


Schema hint

{
  "points":[
    {
      "title":"string",
      "summary":"string",
      "evidence":[{"start_sec":0.0,"end_sec":0.0}]
    }
  ],
  "chapters":[{"title":"string","start_sec":0.0,"end_sec":0.0}]
}

8.2 Translate subtitles (Phi-3 line-by-line)

System

You are a translation engine. Output MUST be valid JSON only.


User

Translate from {SRC} to {DST}.
Return exactly the same number of lines.
Do NOT add explanations.
Input lines:
["line1","line2",...]


Schema hint

{"lines":["...","..."]}


Implementation note: you translate SRT by extracting text lines only, translating, then reinserting with same timestamps.

8.3 Narration script for summary timeline

User

Write narration text for each selected video range. 
Each narration must fit the range duration. Keep it concise.
Output JSON array aligned 1:1 with ranges.
Ranges:
[{"start_sec":..., "end_sec":..., "topic":"..."}]


Schema

{"narration":[{"start_sec":0.0,"end_sec":0.0,"text":"string"}]}

9) Clip planning algorithms (deterministic)
9.1 Fixed split with snapping

Inputs:

target length (e.g., 60s)

transcript segments with start/end

Algorithm:

Start at t=0

propose end = t + 60

snap end to nearest transcript boundary where there is a pause or segment end

ensure min clip 20s

write clip range

t = snapped_end

9.2 Smart split from evidence

Inputs:

evidence ranges from summary

Algorithm:

Normalize: clamp to video duration

Expand to boundaries:

snap start to nearest segment start ≤ start

snap end to nearest segment end ≥ end

Enforce duration min/max (20–60s):

if too long: shrink around most central portion (or split into two)

Remove overlaps, rank, keep top N

10) Dubbing (full replace) — segment-aligned TTS
Input

per-clip translated subtitles (segments with timestamps)

Output

dub_{lang}.wav with same total duration as the clip

Algorithm (per subtitle segment)

For each subtitle line with slot duration slot = end-start:

TTS synth to seg.wav

Measure segDuration

If segDuration > slot:

time-compress using FFmpeg atempo (cap e.g. 1.25)

If segDuration < slot:

append silence for the remaining time

Append to concat list

Finally concat all segments → dub.wav

Then mux:

cut clip video

replace audio with dub.wav

watermark

export mp4

11) Step-by-step implementation milestones (backend-only)
Milestone 1 — Job system + storage + ffprobe

DB + LocalStore + JobQueue + JobRunner

MediaEngine.probe() working
Done when: you can enqueue PROBE job and see progress + DB row updated

Milestone 2 — FFmpeg extract + cut + mux (no AI yet)

extractAudio16kMonoWav

cutClipMp4

overlayWatermark

muxAudioReplace (test with any wav)
Done when: you can create one short locally

Milestone 3 — whisper.cpp transcription once

AsrEngine.transcribeToJson

transcript stored in DB + disk
Done when: transcript.json exists and is reused

Milestone 4 — per-clip subtitles from global transcript

fixedSplit + snap

generate EN SRT per clip without re-whisper
Done when: each clip has en.srt

Milestone 5 — llama.cpp Phi-3 integration (JSON-only)

LlmEngine.completeJson()

Summarize-with-evidence job produces summary.json
Done when: summary.json is valid JSON and evidence ranges are usable

Milestone 6 — Phi-3 subtitle translation

translate SRT lines to hi/ur and reverse
Done when: you can render subtitle variants

Milestone 7 — TTS dubbing full replace

segment-aligned TTS

mux dub.wav
Done when: hi/ur dubbed shorts render locally

Milestone 8 — Summary Builder timeline + narration + combined summary video

build timeline from evidence to reach 10–20 min

generate narration script + TTS narration

concat ranges + mux narration
Done when: summary_video.mp4 is produced locally

12) Practical defaults for Phi-3 Mini Q4_K_M on phone (safe starting point)

llama.cpp inference settings (start)

context: 4096

temperature: 0.2 (keeps JSON stable)

top_p: 0.9

max_tokens:

translate lines: 256–1024 depending on batch size

summarize chunk: 512–1200

chunking:

5–20 min video: 1–2 min chunks

1–2 hour video: 3–5 min chunks (hierarchical summary)

Golden rule: keep each prompt small; run multiple completions rather than one giant completion.

13) What you should implement next (immediately)

If you want the fastest path to a working backend, do this in order:

Milestone 1 + 2 (FFmpeg pipeline + durable job system)

Milestone 3 + 4 (Whisper once + per-clip SRT)

Milestone 5 + 6 (Phi-3 JSON summary + translation)

Milestone 7 (full replace dubbing)

Milestone 8 (combined summary video)

Here’s a backend-only MVP checklist you can tick off step-by-step. Don’t move to the next item until the current one is ✅ done.

Phase 0 — Foundations
✅ 0.1 Local storage layout

 App creates base folder: /ShortsFactory/

 Per asset folder: /assets/{mediaId}/

 Per clip folder: /assets/{mediaId}/clips/{clipId}/

 Cleanup routine exists (delete temp wav/segments on demand)

✅ 0.2 Local DB + tables

 SQLite/Drift integrated

 Tables created: media_assets, transcripts, summaries, clips, subtitles, dubs, renders, pipeline_jobs

 Migrations work (fresh install + upgrade test)

 DB read/write covered with simple DAO functions

✅ 0.3 Job Queue + Runner (resumable)

 pipeline_jobs can be enqueued with kind + payload

 Runner processes jobs sequentially

 Job status updates: QUEUED → RUNNING → DONE/FAILED/RETRY_WAIT/CANCELLED

 App restart resumes unfinished jobs from DB

 Progress events stream implemented (JobEvent)

Phase 1 — FFmpeg Core (no AI yet)
✅ 1.1 FFprobe works

 probe(videoPath) returns duration, width/height, fps, rotation, codecs

 Metadata saved into media_assets

 Tested on: portrait + landscape + rotated videos

✅ 1.2 Audio extraction

 extractAudio16kMonoWav(videoPath) outputs audio_16k_mono.wav

 Output wav plays correctly

 Runtime acceptable on 5–20 min and 1–2 hour test

✅ 1.3 Clip cutting

 cutClip(videoPath, start, end) creates clip_base.mp4

 Clip duration matches requested range (± small tolerance)

 Works across various codecs (H.264/AAC common cases)

✅ 1.4 Watermark overlay

 Overlay watermark PNG applied correctly

 Position configurable

 Output MP4 plays correctly

✅ 1.5 Audio replace mux

 muxAudioReplace(clip.mp4, test.wav) produces output with replaced audio

 Video stream preserved, audio is new (verify by listening)

Gate ✅: You can create a short clip with watermark and replaced audio locally.

Phase 2 — Whisper (Transcribe once)
✅ 2.1 whisper.cpp integration

 transcribe(audio.wav) produces transcript.json

 transcript contains segments[] with {start,end,text}

 Saved in transcripts table with file path

✅ 2.2 “Transcribe once” rule enforced

 If transcript exists for mediaId, runner reuses it

 No per-clip transcription occurs anywhere

Gate ✅: Any imported video can be transcribed once and reused.

Phase 3 — Fixed split + per-clip subtitles (derived)
✅ 3.1 Fixed split planner

 Generates clip ranges (e.g., 60s)

 Stores clips rows with start/end

 Handles long video (1–2h) without memory spikes

✅ 3.2 Snap split boundaries to transcript

 Clip boundaries snap to nearest transcript segment boundary

 Cuts avoid mid-sentence as much as possible

✅ 3.3 Per-clip EN SRT generator

 For each clip, filter transcript segments overlapping the clip

 Rebase timestamps to start at 0.0

 Writes en.srt to clip folder

 SRT is valid (plays in a player)

✅ 3.4 Optional burn-in subtitles

 Burn en.srt into video (optional toggle)

 Output renders correctly

Gate ✅: Shorts Factory can produce: clip.mp4 + en.srt locally.

Phase 4 — Phi-3 (llama.cpp) for Summaries + Translation
✅ 4.1 llama.cpp integration (Phi-3 Mini Q4_K_M)

 Model loads successfully on device

 completeJson() returns valid JSON only (no extra text)

 Memory usage acceptable (no crashes on target device)

✅ 4.2 Summary with evidence (Claude-style)

 Chunk transcript and summarize

 Output summary.json with:

 points[] each having evidence[] ranges {start_sec,end_sec}

 optional chapters[]

 Evidence ranges fall inside transcript duration

 Summary job is resumable (chunk-by-chunk)

✅ 4.3 Smart split from evidence

 Build clip ranges from evidence ranges

 Enforce min/max clip duration (20–60s)

 Remove overlaps and keep top-N

 Store as clips with strategy SMART_EVIDENCE

✅ 4.4 Translation using Phi-3 (SRT line-by-line)

 Extract text lines from SRT

 Translate en→hi, en→ur (and reverse hi/ur→en)

 Reinsert lines into SRT with same timestamps

 Outputs hi.srt, ur.srt are valid

Gate ✅: App can create smart clips + translated subtitle files locally.

Phase 5 — Dubbing (full audio replace)
✅ 5.1 System TTS integration

 Can synthesize WAV for en, hi, ur

 Detect and handle “voice not available”

 Store voice choice (voice_id)

✅ 5.2 Segment-aligned dub builder

 For each subtitle segment:

 TTS generate seg.wav

 Fit to slot duration (compress if too long, pad if too short)

 Concatenate into dub_{lang}.wav

 Dub duration matches clip duration (± small tolerance)

✅ 5.3 Render dubbed clip variants

 Mux dub_hi.wav → clip_hi.mp4 (full replace)

 Mux dub_ur.wav → clip_ur.mp4

 Optional: burn hi.srt/ur.srt

 Save outputs in renders table

Gate ✅: You can generate Hindi/Urdu dubbed shorts locally.

Phase 6 — Summary Video (combine parts + new narration audio)
✅ 6.1 Build summary timeline (10/15/20 min)

 Select evidence ranges until target duration reached

 Snap to transcript boundaries

 Save ordered list of ranges (timeline)

✅ 6.2 Generate narration script (Phi-3)

 Produce per-range narration text

 Keep narration short enough to fit each range

✅ 6.3 Narration TTS (full replace)

 Generate narration WAV per range

 Align duration to range (compress/pad)

 Concatenate to narration.wav matching combined video length

✅ 6.4 Render combined summary video

 Cut all timeline ranges into temporary clips

 Concatenate to one summary_video.mp4

 Replace audio with narration.wav (full replace)

 Save output in DB

Gate ✅: 1–2 hour video → 10–20 min summary video with new narration audio, fully local.

Phase 7 — Reliability gates (do before UI polish)
✅ 7.1 Resumability

 Kill app mid-transcribe, reopen → resumes

 Kill app mid-render, reopen → resumes

 Partial files cleaned safely

✅ 7.2 Device constraints

 “Only process when charging” option supported in backend config

 “Stop if low battery/thermal” checks (basic)

 Sequential processing confirmed (no runaway parallelism)

✅ 7.3 Output verification

 All MP4 outputs playable

 All SRT outputs valid

 Audio replace actually replaced (no original audio leaking)