/**
 * Queue worker (improved / hardened version)
 * - More robust SRT parsing/building
 * - Safer token budgeting
 * - Better Bedrock JSON extraction + timestamp validation
 * - More stable audio handling (avoid fragile -c:a copy by default for cuts/concat)
 * - Atomic final writes when generating/burning subtitles
 * - Fallback scene selection when threshold yields nothing
 * - Small operational improvements (timeouts, ffmpeg filter caching)
 */

const fs = require('fs/promises');
const fsSync = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const { BedrockRuntimeClient, InvokeModelCommand } =
  require('@aws-sdk/client-bedrock-runtime');

const db = require('../database/db');

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const UPLOAD_ROOT = path.resolve(UPLOAD_DIR);

const FFMPEG = process.env.FFMPEG_BIN || 'ffmpeg';
const FFPROBE = process.env.FFPROBE_BIN || 'ffprobe';
const WHISPER_BIN = process.env.WHISPER_BIN || '';
const WHISPER_MODEL = process.env.WHISPER_MODEL || '';
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || '').replace(/\/+$/, '');

const MAX_TOKENS_OUT = parseInt(process.env.BEDROCK_MAX_TOKENS_OUT || '4096', 10);
const MAX_INPUT_TOKENS = parseInt(process.env.BEDROCK_MAX_INPUT_TOKENS || '120000', 10);
const PROMPT_OVERHEAD_TOKENS = parseInt(process.env.BEDROCK_PROMPT_OVERHEAD_TOKENS || '1200', 10);

const DEFAULT_CANVAS_WIDTH = 1080;
const DEFAULT_CANVAS_HEIGHT = 1920;
const DEFAULT_WATERMARK_WIDTH = 260;
const DEFAULT_WATERMARK_ALPHA = 0.55;
const DEFAULT_SRT_CHUNK_SIZE = parseInt(process.env.SRT_CHUNK_SIZE || '250', 10);
const DEFAULT_SUMMARY_MAX_INPUT_TOKENS = parseInt(
  process.env.SUMMARY_MAX_INPUT_TOKENS || '12000',
  10
);
const DEFAULT_SUMMARY_PROMPT_OVERHEAD_TOKENS = parseInt(
  process.env.SUMMARY_PROMPT_OVERHEAD_TOKENS || '1200',
  10
);
const DEFAULT_MIN_SCENE_SEC = 60;
const DEFAULT_MAX_SCENE_SEC = 600;
const DEFAULT_SCENE_PADDING_SEC = 5;
const DEFAULT_STORY_MEMORY_CHARS = parseInt(process.env.STORY_MEMORY_CHARS || '1400', 10);
const DEFAULT_MIN_TTS_SEC = parseFloat(process.env.MIN_TTS_SEC || '6');
const DEFAULT_MAX_TTS_SEC = parseFloat(process.env.MAX_TTS_SEC || '45');
const DEFAULT_TTS_FADE_SEC = parseFloat(process.env.TTS_FADE_SEC || '0.1');
const DEFAULT_TTS_ORIGINAL_VOL = parseFloat(process.env.TTS_ORIGINAL_VOL || '0.35');
const DEFAULT_TTS_VOICE_VOL = parseFloat(process.env.TTS_VOICE_VOL || '1.0');
const DEFAULT_TTS_VOICE = String(process.env.TTS_VOICE || 'Samantha');
const DEFAULT_MAX_SPEEDUP = parseFloat(process.env.MAX_SPEEDUP || '1.35');
const DEFAULT_MIN_SLOWDOWN = parseFloat(process.env.MIN_SLOWDOWN || '0.85');
const DEFAULT_DUCK_VOLUME = parseFloat(process.env.DUCK_VOLUME || '0.18');
const DEFAULT_SUMMARY_MIN_SEG_SEC = parseFloat(process.env.SUMMARY_MIN_SEG_SEC || '25');
const DEFAULT_SUMMARY_MAX_SEG_SEC = parseFloat(process.env.SUMMARY_MAX_SEG_SEC || '60');
const TTS_ENGINE = String(process.env.TTS_ENGINE || 'kokoro').toLowerCase();
const KOKORO_MODEL_ID = String(process.env.KOKORO_MODEL_ID || 'onnx-community/Kokoro-82M-v1.0-ONNX');
const KOKORO_DTYPE = String(process.env.KOKORO_DTYPE || 'q8');

let kokoroInstance = null;
let kokoroInitPromise = null;
const TEXT_MARGIN_X = 60;
const TEXT_MARGIN_Y = 200;
const TEXT_MAX_X = 860;
const TEXT_MAX_Y = 1400;
const WATERMARK_MARGIN = 40;

const WORKER_INTERVAL_MS = parseInt(process.env.WORKER_INTERVAL_MS || '2000', 10);
const WORKER_CONCURRENCY = parseInt(process.env.WORKER_CONCURRENCY || '1', 10);

// New: prefer stability; audio copy is fragile for cut+concat. You can override via env.
const PREFER_AUDIO_COPY = String(process.env.PREFER_AUDIO_COPY || '').toLowerCase() === 'true';

// New: command timeout (ms). Prevent jobs stuck on bad inputs.
const COMMAND_TIMEOUT_MS = parseInt(process.env.COMMAND_TIMEOUT_MS || '0', 10); // 0 = no timeout

let running = 0;
let timer = null;
let drawtextAvailable = null;
let subtitlesAvailable = null;
let ffmpegFiltersCache = null;

function startQueueWorker(io) {
  if (timer) return;
  timer = setInterval(() => tick(io), WORKER_INTERVAL_MS);
  console.log('[worker] Queue worker started');
}

async function tick(io) {
  if (running >= WORKER_CONCURRENCY) return;
  const job = await claimNextJob();
  if (!job) return;
  running += 1;
  processJob(job, io)
    .catch((err) => console.error('[worker] job failed', err))
    .finally(() => {
      running -= 1;
    });
}

async function claimNextJob() {
  const rows = await db.allAsync(
    `SELECT qj.*, p.settings_json, p.user_id, p.title as project_title,
            v.file_path, v.filename
     FROM queue_jobs qj
     JOIN projects p ON qj.project_id = p.id
     JOIN videos v ON qj.video_id = v.id
     WHERE qj.status = 'pending'
     ORDER BY qj.created_at ASC
     LIMIT 10`
  );

  for (const row of rows) {
    const settings = safeJson(row.settings_json) || {};
    const mode = (settings.processing_mode || '').toString().toLowerCase();
    const category = (settings.category || '').toString().toLowerCase();
    const isAiBestScenes =
      mode === 'ai_best_scenes' || category === 'summary' || mode.startsWith('ai_');

    if (!isAiBestScenes) continue;
    if (!row.file_path) continue;

    const updated = await db.runAsync(
      `UPDATE queue_jobs
       SET status = 'running', started_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'pending'`,
      [row.id]
    );
    if (updated.changes === 0) continue;

    return row;
  }

  return null;
}

async function processJob(job, io) {
  const jobId = job.id;
  const projectId = job.project_id;
  const userId = job.user_id;
  const videoPath = path.isAbsolute(job.file_path) ? job.file_path : path.resolve(job.file_path);
  const videoFilename = job.filename || 'video.mp4';

  const settings = safeJson(job.settings_json) || {};
  // const aiSettings = settings.ai_best_scenes || {};
  const aiSettings = settings.ai_best_scenes || {};
  const processingMode = String(settings.processing_mode || '').toLowerCase();
  const isAiSplitMode = processingMode === 'ai_best_scenes_split';

  const options = {
    // chunking: if 0 => use token budget (good)
    srtChunkSize: normalizeLimit(aiSettings.srt_chunk_size), // 0 => null

    // IMPORTANT: duration defaults
    minSceneSec:
      normalizeLimit(aiSettings.min_scene_sec) ?? DEFAULT_MIN_SCENE_SEC,
    maxSceneSec:
      normalizeLimit(aiSettings.max_scene_sec) ??
      (isAiSplitMode ? 90 : DEFAULT_MAX_SCENE_SEC),

    // selection knobs
    scoreThreshold: Number.isFinite(Number(aiSettings.score_threshold))
      ? Number(aiSettings.score_threshold)
      : 72,

    minGapSec: Number.isFinite(Number(aiSettings.min_gap_sec))
      ? Number(aiSettings.min_gap_sec)
      : 2.0,

    // IMPORTANT: if 0 => unlimited (Infinity)
    maxScenes: normalizeLimit(aiSettings.max_scenes),       // null => Infinity in selector
    maxTotalSec: normalizeLimit(aiSettings.max_total_sec), // null => Infinity in selector

    // IMPORTANT: if 0/undefined => default to 3 for split-clip mode, else 1
    segmentsPerChunk:
      Number(aiSettings.segments_per_chunk || 0) > 0
        ? Number(aiSettings.segments_per_chunk)
        : isAiSplitMode
          ? 3
          : 1,

    contextOverlap: (() => {
      const raw = Number(aiSettings.context_overlap || 0);
      if (Number.isFinite(raw) && raw > 0) return Math.floor(raw);
      if (processingMode === 'ai_summary_hybrid' || processingMode === 'ai_story_only') {
        return 6;
      }
      return 0;
    })(),

    scenePaddingSec:
      normalizeLimit(aiSettings.scene_padding_sec) ??
      DEFAULT_SCENE_PADDING_SEC,

    maxInputTokens: MAX_INPUT_TOKENS,
    promptOverheadTokens: PROMPT_OVERHEAD_TOKENS,

    storyMemoryChars:
      normalizeLimit(aiSettings.story_memory_chars) ??
      DEFAULT_STORY_MEMORY_CHARS,
    minTtsSec:
      Number.isFinite(Number(aiSettings.min_tts_sec))
        ? Number(aiSettings.min_tts_sec)
        : DEFAULT_MIN_TTS_SEC,
    maxTtsSec:
      Number.isFinite(Number(aiSettings.max_tts_sec))
        ? Number(aiSettings.max_tts_sec)
        : DEFAULT_MAX_TTS_SEC,
    ttsFadeSec:
      Number.isFinite(Number(aiSettings.tts_fade_sec))
        ? Number(aiSettings.tts_fade_sec)
        : DEFAULT_TTS_FADE_SEC,
    ttsVoice: String(aiSettings.tts_voice || DEFAULT_TTS_VOICE),
    ttsOriginalVol:
      Number.isFinite(Number(aiSettings.tts_original_vol))
        ? Number(aiSettings.tts_original_vol)
        : DEFAULT_TTS_ORIGINAL_VOL,
    ttsVoiceVol:
      Number.isFinite(Number(aiSettings.tts_voice_vol))
        ? Number(aiSettings.tts_voice_vol)
        : DEFAULT_TTS_VOICE_VOL,
    maxSpeedup:
      Number.isFinite(Number(aiSettings.max_speedup))
        ? Number(aiSettings.max_speedup)
        : DEFAULT_MAX_SPEEDUP,
    minSlowdown:
      Number.isFinite(Number(aiSettings.min_slowdown))
        ? Number(aiSettings.min_slowdown)
        : DEFAULT_MIN_SLOWDOWN,
    duckVolume:
      Number.isFinite(Number(aiSettings.duck_volume))
        ? Number(aiSettings.duck_volume)
        : DEFAULT_DUCK_VOLUME,
    summaryMinSegSec:
      Number.isFinite(Number(aiSettings.summary_min_seg_sec))
        ? Number(aiSettings.summary_min_seg_sec)
        : DEFAULT_SUMMARY_MIN_SEG_SEC,
    summaryMaxSegSec:
      Number.isFinite(Number(aiSettings.summary_max_seg_sec))
        ? Number(aiSettings.summary_max_seg_sec)
        : DEFAULT_SUMMARY_MAX_SEG_SEC,
    summaryPlanOnly: aiSettings.summary_plan_only === true,
    summarySegmentsPerChunk:
      Number.isFinite(Number(aiSettings.summary_segments_per_chunk))
        ? Math.max(1, Math.floor(Number(aiSettings.summary_segments_per_chunk)))
        : 1,
    summaryMaxSegments:
      Number.isFinite(Number(aiSettings.summary_max_segments))
        ? Math.max(0, Math.floor(Number(aiSettings.summary_max_segments)))
        : 0,
  };

  const overlaySettings = {
    flipMode: String(settings.flip_mode || 'none').toLowerCase(),
    watermarkEnabled: settings.watermark_enabled !== false,
    watermarkPosition: String(settings.watermark_position || 'bottom_right').toLowerCase(),
    watermarkAlpha: Number.isFinite(Number(settings.watermark_alpha))
      ? Number(settings.watermark_alpha)
      : DEFAULT_WATERMARK_ALPHA,
    channelName: String(settings.channel_name || '').trim(),
    textRandomPosition: settings.text_random_position !== false,
    outputResolution: String(settings.output_resolution || '1080x1920'),
    subtitlesEnabled: settings.subtitles_enabled === true,
  };

  await updateJob(io, userId, jobId, {
    status: 'running',
    progress: 0.05,
    error_message: 'Starting backend pipeline',
  });
  await updateProjectProgress(projectId, 'processing');

  try {
    const workDir = path.join(UPLOAD_ROOT, 'projects', projectId);
    await fs.mkdir(workDir, { recursive: true });

    // 1) Extract audio
    const wavPath = path.join(workDir, 'audio_16k.wav');
    await updateJob(io, userId, jobId, { progress: 0.1, error_message: 'Extract audio' });

    if (!(await exists(wavPath))) {
      await runCommand(FFMPEG, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        videoPath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        wavPath,
      ]);
    }

    // 2) Transcribe
    const srtPath = path.join(workDir, 'transcript.srt');
    await updateJob(io, userId, jobId, { progress: 0.2, error_message: 'Transcribe audio to SRT' });
    if (!(await exists(srtPath))) {
      await transcribeToSrt(wavPath, srtPath);
    }

    const rawSrt = await fs.readFile(srtPath, 'utf8');
    const transcriptItems = parseSrt(rawSrt);

    await updateJob(io, userId, jobId, {
      progress: 0.25,
      error_message: `Transcription complete | items=${transcriptItems.length}`,
    });

    if (!transcriptItems.length) {
      throw new Error('Transcript is empty (no subtitle items parsed).');
    }

    // 3) Duration
    let totalDuration = await probeDuration(videoPath);
    if (!totalDuration && transcriptItems.length > 0) {
      totalDuration = transcriptItems[transcriptItems.length - 1].endSec;
    }

    // 4) Chunking (token-safe)
    const chunks = (() => {
      const isSummaryMode =
        processingMode === 'ai_summary_hybrid' || processingMode === 'ai_story_only';

      if (isSummaryMode) {
        // Summary/story: only use SRT item chunking if user explicitly set it
        if (options.srtChunkSize && options.srtChunkSize > 0) {
          return chunkByItemCount(transcriptItems, options.srtChunkSize);
        }
        // Default: token-budget chunking (matches "auto chunk" UI)
        return chunkByTokenBudget(
          transcriptItems,
          DEFAULT_SUMMARY_MAX_INPUT_TOKENS,
          DEFAULT_SUMMARY_PROMPT_OVERHEAD_TOKENS
        );
      }

      // Non-summary: use SRT item chunking only if explicitly set, else token budget
      if (options.srtChunkSize && options.srtChunkSize > 0) {
        return chunkByItemCount(transcriptItems, options.srtChunkSize);
      }
      return chunkByTokenBudget(transcriptItems, options.maxInputTokens, options.promptOverheadTokens);
    })();


    if (processingMode === 'ai_summary_hybrid' || processingMode === 'ai_story_only') {
      await processStorySummary(io, {
        jobId,
        userId,
        projectId,
        videoPath,
        videoFilename,
        transcriptItems,
        chunks,
        totalDuration,
        options,
        overlaySettings,
        workDir,
        processingMode,
      });
      return;
    }


    await updateJob(io, userId, jobId, {
      progress: 0.3,
      error_message: `Analyze transcript with AI | chunks=${chunks.length}`,
    });

    // 5) Analyze
    const scenes = await analyzeChunks(io, userId, jobId, projectId, chunks, options, totalDuration);

    if (!scenes.length) {
      // New: softer fallback
      const relaxed = { ...options, scoreThreshold: Math.max(40, (options.scoreThreshold || 72) - 20), minGapSec: 0.5 };
      const fallback = selectBestNonOverlapping(
        chunks.flatMap((ch) => heuristicAnalyze(ch, relaxed)),
        relaxed
      );
      if (!fallback.length) {
        throw new Error('AI could not detect best scenes from transcript (even after fallback).');
      }
      scenes.push(...fallback);
    }

    await writeSceneTranscripts(transcriptItems, scenes, workDir);

    // 6) Segment
    await updateJob(io, userId, jobId, { progress: 0.8, error_message: 'Cutting highlight clips' });

    const clipsDir = path.join(workDir, 'clips');
    await fs.mkdir(clipsDir, { recursive: true });

    const clipPaths = [];
    const clipMeta = [];

    // Audio strategy: stable for cuts/concat
    const audioInfo = await probeAudioInfo(videoPath);
    const audioMode = pickAudioMode(audioInfo);

    const watermarkPath = resolveWatermarkPath(overlaySettings);
    if (overlaySettings.watermarkEnabled && !watermarkPath) {
      console.warn('[worker] Watermark enabled but no watermark file found.');
    }
    if (overlaySettings.channelName && !hasDrawtextFilter()) {
      console.warn('[worker] drawtext filter not available; channel name overlay skipped.');
    }

    for (let i = 0; i < scenes.length; i += 1) {
      const s = scenes[i];
      const dur = Math.max(0.2, s.endSec - s.startSec).toFixed(3);
      const start = s.startSec.toFixed(3);

      const clipPath = path.join(clipsDir, `scene_${String(i + 1).padStart(3, '0')}.mp4`);
      const overlayConfig = buildOverlayConfig(overlaySettings, watermarkPath);

      const { audioMapArgs, audioArgs, audioFilterArgs } = buildAudioArgs(audioMode, { forCut: true });

      const videoMapArgs = overlayConfig.useComplex ? ['-map', '[v]'] : ['-map', '0:v:0'];
      const mapArgs = [...videoMapArgs, ...audioMapArgs];

      await runCommand(FFMPEG, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        // keep fast seek, but stability from re-encoding audio (not copy)
        '-ss',
        start,
        '-t',
        dur,
        '-i',
        videoPath,
        ...overlayConfig.inputArgs,
        ...overlayConfig.filterArgs,
        ...mapArgs,
        ...audioFilterArgs,
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-pix_fmt',
        'yuv420p',
        ...audioArgs,
        ...overlayConfig.outputArgs,
        '-movflags',
        '+faststart',
        clipPath,
      ]);

      clipPaths.push(clipPath);
      const clipDuration = (await probeDuration(clipPath)) || (s.endSec - s.startSec);
      clipMeta.push({ startSec: s.startSec, endSec: s.endSec, durationSec: clipDuration });

      const ratio = (i + 1) / scenes.length;
      await updateJob(io, userId, jobId, {
        progress: 0.8 + 0.1 * ratio,
        error_message: `Cut clips ${i + 1}/${scenes.length} (remaining ${scenes.length - (i + 1)})`,
      });
    }

    if (isAiSplitMode) {
      await updateJob(io, userId, jobId, {
        progress: 0.92,
        error_message: 'Saving best-scene clips',
      });

      const outputDir = path.join(workDir, 'result');
      await fs.mkdir(outputDir, { recursive: true });

      const outputs = [];
      for (let i = 0; i < clipPaths.length; i += 1) {
        const srcPath = clipPaths[i];
        const outputFilename = makeOutputFilename(videoFilename, i);
        const outputPath = path.join(outputDir, outputFilename);
        await fs.copyFile(srcPath, outputPath);

        if (overlaySettings.subtitlesEnabled) {
          const sceneSrt = path.join(
            workDir,
            'clips',
            `scene_${String(i + 1).padStart(3, '0')}.srt`
          );
          if (await exists(sceneSrt)) {
            const subbedTmp = `${outputPath}.subbed_tmp_${Date.now()}.mp4`;
            const burned = await burnSubtitles(
              outputPath,
              sceneSrt,
              subbedTmp,
              audioMode
            );
            if (burned) {
              await fs.unlink(outputPath).catch(() => { });
              await fs.rename(subbedTmp, outputPath);
            } else {
              await fs.unlink(subbedTmp).catch(() => { });
            }
          }
        }

        const sizeBytes = await safeStatSize(outputPath);
        const durationSec = await probeDuration(outputPath);
        const outputId = uuidv4();
        await db.runAsync(
          `INSERT INTO output_videos
           (id, project_id, job_id, chunk_index, filename, file_path, duration_sec, size_bytes)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            outputId,
            projectId,
            jobId,
            i,
            outputFilename,
            outputPath,
            durationSec || null,
            sizeBytes || null,
          ]
        );

        outputs.push({
          id: outputId,
          filename: outputFilename,
          file_path: outputPath,
        });

        if (io && userId) {
          const output = await db.getAsync(
            'SELECT * FROM output_videos WHERE id = ?',
            [outputId]
          );
          io.to(`user:${userId}`).emit('output:created', {
            output,
            timestamp: new Date().toISOString(),
          });
        }
      }

      const primary = outputs[0];
      await updateJob(io, userId, jobId, {
        status: 'completed',
        progress: 1.0,
        output_filename: primary?.filename ?? null,
        output_path: primary?.file_path ? toPublicUrl(primary.file_path) : null,
        error_message: null,
      });

      await updateProjectProgress(projectId, 'completed');
      return;
    }

    // 7) Merge
    await updateJob(io, userId, jobId, { progress: 0.92, error_message: 'Merging final video' });

    const outputDir = path.join(workDir, 'result');
    await fs.mkdir(outputDir, { recursive: true });

    const outputFilename = makeOutputFilename(videoFilename, 0);
    const outputPath = path.join(outputDir, outputFilename);

    if (clipPaths.length === 0) throw new Error('No clips produced to merge');

    // Atomic write path
    const tmpOutput = `${outputPath}.tmp_${Date.now()}.mp4`;

    if (clipPaths.length === 1) {
      await fs.copyFile(clipPaths[0], tmpOutput);
    } else {
      await concatClips(clipPaths, tmpOutput, workDir, audioMode);
    }

    // 8) Subtitles burn (optional)
    if (overlaySettings.subtitlesEnabled) {
      if (!hasSubtitlesFilter()) {
        console.warn('[worker] subtitles filter not available; subtitle burn skipped.');
      } else {
        const mergedSrtPath = path.join(workDir, 'highlights_merged.srt');
        const wrote = await writeMergedSrt(transcriptItems, clipMeta, mergedSrtPath);

        if (wrote) {
          const subbedTmp = `${outputPath}.subbed_tmp_${Date.now()}.mp4`;
          const burned = await burnSubtitles(tmpOutput, mergedSrtPath, subbedTmp, audioMode);
          if (burned) {
            await fs.unlink(tmpOutput).catch(() => { });
            await fs.rename(subbedTmp, tmpOutput);
          } else {
            await fs.unlink(subbedTmp).catch(() => { });
          }
        } else {
          console.warn('[worker] Subtitles enabled but merged SRT is empty.');
        }
      }
    }

    // Finalize atomically
    await fs.rename(tmpOutput, outputPath);

    const publicOutputPath = toPublicUrl(outputPath);
    const sizeBytes = await safeStatSize(outputPath);
    const durationSec = await probeDuration(outputPath);

    const outputId = uuidv4();
    await db.runAsync(
      `INSERT INTO output_videos
       (id, project_id, job_id, chunk_index, filename, file_path, duration_sec, size_bytes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [outputId, projectId, jobId, 0, outputFilename, outputPath, durationSec || null, sizeBytes || null]
    );

    await updateJob(io, userId, jobId, {
      status: 'completed',
      progress: 1.0,
      output_filename: outputFilename,
      output_path: publicOutputPath,
      error_message: null,
    });

    await updateProjectProgress(projectId, 'completed');

    if (io && userId) {
      const output = await db.getAsync('SELECT * FROM output_videos WHERE id = ?', [outputId]);
      io.to(`user:${userId}`).emit('output:created', {
        output,
        timestamp: new Date().toISOString(),
      });
    }
  } catch (err) {
    await updateJob(io, userId, jobId, {
      status: 'failed',
      error_message: err.message || 'Backend processing failed',
    });
    await updateProjectProgress(projectId, 'failed');
    throw err;
  }
}

async function narrateSceneWithBedrock(sceneSrtText, storySoFar, sceneIndex) {
  if (!hasBedrockConfig()) return null;

  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
  const modelId = process.env.BEDROCK_MODEL_ID || 'eu.anthropic.claude-sonnet-4-20250514-v1:0';
  const credentials = getAwsCredentialsFromEnv();

  const prompt = `
You are writing a short narrated summary for a selected highlight scene from a video.

Rules:
- Do NOT translate. Write in the SAME language as the transcript.
- Write 1–2 sentences max, cinematic, story voice.
- Focus on the key point / reveal / conflict / decision.
- Avoid filler and greetings.
- Output JSON only. No markdown, no extra text.

Return JSON:
{
  "story_text": "..."
}

Story continuity (optional; keep consistent, do not repeat verbatim):
${storySoFar || '(none)'}

SCENE TRANSCRIPT (SRT text):
${sceneSrtText}
  `.trim();

  const client = new BedrockRuntimeClient(credentials ? { region, credentials } : { region });
  const body = {
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: Math.min(Number.isNaN(MAX_TOKENS_OUT) ? 4096 : MAX_TOKENS_OUT, 2048),
    temperature: 0.2,
    messages: [{ role: 'user', content: [{ type: 'text', text: prompt }] }],
  };

  const response = await client.send(
    new InvokeModelCommand({
      modelId,
      contentType: 'application/json',
      accept: 'application/json',
      body: JSON.stringify(body),
    })
  );

  const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'));
  const text =
    decoded?.content?.find?.((c) => c?.type === 'text')?.text ||
    decoded?.output_text ||
    '';

  const parsed = extractJsonObject(text);
  const storyText = String(parsed?.story_text || parsed?.storyText || '').trim();
  if (!storyText) return null;
  return storyText;
}
async function processSummaryFromBestScenes(
  io,
  {
    jobId,
    userId,
    projectId,
    videoPath,
    videoFilename,
    transcriptItems,
    chunks,
    totalDuration,
    options,
    overlaySettings,
    workDir,
    processingMode, // 'ai_summary_hybrid' | 'ai_story_only'
  }
) {
  if (!hasBedrockConfig()) {
    throw new Error('Bedrock not configured for AI summary.');
  }

  await updateJob(io, userId, jobId, {
    progress: 0.3,
    error_message: `Select best scenes for summary | chunks=${chunks.length}`,
  });

  // 1) Pick best scenes (global selection across all transcript chunks)
  const scenes = await analyzeChunks(io, userId, jobId, projectId, chunks, options, totalDuration);

  if (!scenes.length) {
    throw new Error('No scenes detected for summary. Try lowering score_threshold or min_scene_sec.');
  }

  // 2) Write per-scene SRTs (so we can narrate each scene’s transcript)
  await writeSceneTranscripts(transcriptItems, scenes, workDir);

  const segmentsDir = path.join(workDir, 'summary_segments');
  const chunksDir = path.join(workDir, 'summary_debug');
  await fs.mkdir(segmentsDir, { recursive: true });
  await fs.mkdir(chunksDir, { recursive: true });

  const watermarkPath = resolveWatermarkPath(overlaySettings);
  if (overlaySettings.watermarkEnabled && !watermarkPath) {
    console.warn('[worker] Watermark enabled but no watermark file found.');
  }
  if (overlaySettings.channelName && !hasDrawtextFilter()) {
    console.warn('[worker] drawtext filter not available; channel name overlay skipped.');
  }

  // Audio handling
  const audioInfo = await probeAudioInfo(videoPath);
  const audioMode = pickAudioMode(audioInfo);

  // Story continuity memory (optional)
  let storySoFar = '';
  const finalSceneFiles = [];
  const narrationsDebug = [];

  // Scenes SRT directory from writeSceneTranscripts()
  const clipsSrtDir = path.join(workDir, 'clips');

  await updateJob(io, userId, jobId, {
    progress: 0.45,
    error_message: `Narrate & render summary scenes | scenes=${scenes.length}`,
  });

  // 3) For each selected scene: narrate, TTS, cut, mix
  for (let i = 0; i < scenes.length; i += 1) {
    const sceneIndex = i + 1;
    const s = scenes[i];

    const ratio = (i + 1) / Math.max(1, scenes.length);
    await updateJob(io, userId, jobId, {
      progress: 0.45 + 0.45 * ratio,
      error_message: `Render summary scene ${sceneIndex}/${scenes.length}`,
    });

    // Read that scene’s SRT text
    const sceneSrtPath = path.join(clipsSrtDir, `scene_${String(sceneIndex).padStart(3, '0')}.srt`);
    const sceneSrtText = await fs.readFile(sceneSrtPath, 'utf8').catch(() => '');

    // If for some reason file is empty, fallback: build from transcriptItems
    const sceneTextForLLM = sceneSrtText || buildSceneSrt(transcriptItems, s.startSec, s.endSec);

    // Ask Bedrock for a 1–2 sentence narration for this scene only
    const narration = await narrateSceneWithBedrock(sceneTextForLLM, storySoFar, sceneIndex);
    if (!narration) {
      narrationsDebug.push({ sceneIndex, startSec: s.startSec, endSec: s.endSec, skipped: true, reason: 'no_narration' });
      continue;
    }

    narrationsDebug.push({
      sceneIndex,
      startSec: s.startSec,
      endSec: s.endSec,
      score: s.score,
      why: s.why,
      narration,
    });

    // Update continuity memory (optional)
    storySoFar = `${storySoFar} ${narration}`.trim();
    if (storySoFar.length > options.storyMemoryChars) {
      storySoFar = storySoFar.slice(-options.storyMemoryChars);
    }

    // Clamp times
    let start = Number(s.startSec);
    let end = Number(s.endSec);
    if (Number.isFinite(totalDuration) && totalDuration > 0) {
      start = clamp(start, 0, totalDuration);
      end = clamp(end, 0, totalDuration);
    }
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start + 0.5) {
      continue;
    }

    const clipDur = end - start;

    // Cut base scene clip with overlays (watermark/text/flip/scale/pad)
    const segTag = String(sceneIndex).padStart(3, '0');
    const clipBase = path.join(segmentsDir, `scene_${segTag}_base.mp4`);

    const overlayConfig = buildOverlayConfig(overlaySettings, watermarkPath);
    const { audioMapArgs, audioArgs, audioFilterArgs } = buildAudioArgs(audioMode, { forCut: true });
    const videoMapArgs = overlayConfig.useComplex ? ['-map', '[v]'] : ['-map', '0:v:0'];
    const mapArgs = [...videoMapArgs, ...audioMapArgs];

    await runCommand(FFMPEG, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-ss',
      start.toFixed(3),
      '-t',
      clipDur.toFixed(3),
      '-i',
      videoPath,
      ...overlayConfig.inputArgs,
      ...overlayConfig.filterArgs,
      ...mapArgs,
      ...audioFilterArgs,
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      ...audioArgs,
      ...overlayConfig.outputArgs,
      '-movflags',
      '+faststart',
      clipBase,
    ]);

    // TTS generate and fit to segment duration (no padding)
    const rawTts = path.join(segmentsDir, `scene_${segTag}_tts_raw.wav`);
    const fitTts = path.join(segmentsDir, `scene_${segTag}_tts_fit.wav`);
    await ttsGenerateWav(narration, rawTts, options.ttsVoice);
    await fitTtsToSegmentNoPad(rawTts, fitTts, clipDur, options.maxSpeedup, options.minSlowdown);

    // Mix
    const clipFinal = path.join(segmentsDir, `scene_${segTag}_final.mp4`);
    if (processingMode === 'ai_summary_hybrid') {
      await mixTtsOverOriginalDuck(clipBase, fitTts, clipFinal, options.duckVolume, options.ttsFadeSec);
    } else {
      // story_only: replace audio completely
      await muxReplaceAudio(clipBase, fitTts, clipFinal);
    }

    finalSceneFiles.push(clipFinal);
  }

  await fs.writeFile(
    path.join(chunksDir, 'summary_narrations.json'),
    JSON.stringify(narrationsDebug, null, 2),
    'utf8'
  );

  if (!finalSceneFiles.length) {
    throw new Error('No summary scenes produced (all narrations failed or invalid). Check summary_debug/summary_narrations.json');
  }

  // 4) Concat narrated scenes into final output
  await updateJob(io, userId, jobId, { progress: 0.92, error_message: 'Merging summary video (best scenes)' });

  const outputDir = path.join(workDir, 'result');
  await fs.mkdir(outputDir, { recursive: true });

  const outputFilename = makeOutputFilename(videoFilename, 0);
  const outputPath = path.join(outputDir, outputFilename);
  const tmpOutput = `${outputPath}.tmp_${Date.now()}.mp4`;

  if (finalSceneFiles.length === 1) {
    await fs.copyFile(finalSceneFiles[0], tmpOutput);
  } else {
    await concatClips(finalSceneFiles, tmpOutput, workDir, 'aac');
  }

  await fs.rename(tmpOutput, outputPath);

  const publicOutputPath = toPublicUrl(outputPath);
  const sizeBytes = await safeStatSize(outputPath);
  const durationSec = await probeDuration(outputPath);

  const outputId = uuidv4();
  await db.runAsync(
    `INSERT INTO output_videos
     (id, project_id, job_id, chunk_index, filename, file_path, duration_sec, size_bytes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [outputId, projectId, jobId, 0, outputFilename, outputPath, durationSec || null, sizeBytes || null]
  );

  await updateJob(io, userId, jobId, {
    status: 'completed',
    progress: 1.0,
    output_filename: outputFilename,
    output_path: publicOutputPath,
    error_message: null,
  });

  // Clean up selection so re-renders can re-run analysis
  const selectionPath = path.join(workDir, 'summary_selection.json');
  await fs.unlink(selectionPath).catch(() => {});

  await updateProjectProgress(projectId, 'completed');

  if (io && userId) {
    const output = await db.getAsync('SELECT * FROM output_videos WHERE id = ?', [outputId]);
    io.to(`user:${userId}`).emit('output:created', {
      output,
      timestamp: new Date().toISOString(),
    });
  }
}

async function processStorySummary(
  io,
  {
    jobId,
    userId,
    projectId,
    videoPath,
    videoFilename,
    transcriptItems,
    chunks,
    totalDuration,
    options,
    overlaySettings,
    workDir,
    processingMode,
  }
) {
  if (!hasBedrockConfig()) {
    throw new Error('Bedrock not configured for AI summary.');
  }

  const segmentsDir = path.join(workDir, 'story_segments');
  const chunksDir = path.join(workDir, 'story_chunks');
  await fs.mkdir(segmentsDir, { recursive: true });
  await fs.mkdir(chunksDir, { recursive: true });

  const selectionPath = path.join(workDir, 'summary_selection.json');
  const candidatesPath = path.join(workDir, 'summary_candidates.json');

  const watermarkPath = resolveWatermarkPath(overlaySettings);

  const finalSceneFiles = [];
  const debugChunks = [];
  let storySoFar = '';
  let lastEnd = -1;

  const overlapItems = Math.max(0, options.contextOverlap || 0);
  const segmentsPerChunk =
    Number.isFinite(Number(options.summarySegmentsPerChunk)) && Number(options.summarySegmentsPerChunk) > 0
      ? Math.floor(Number(options.summarySegmentsPerChunk))
      : 1;
  const maxSegments =
    Number.isFinite(Number(options.summaryMaxSegments)) && Number(options.summaryMaxSegments) > 0
      ? Math.floor(Number(options.summaryMaxSegments))
      : Infinity;

  const audioInfo = await probeAudioInfo(videoPath);
  const audioMode = pickAudioMode(audioInfo);

  // If user already selected scenes, skip analysis and render directly.
  if (await exists(selectionPath)) {
    const raw = await fs.readFile(selectionPath, 'utf8').catch(() => '');
    const parsed = raw ? safeJson(raw) : null;
    const matchesJob = parsed && parsed.jobId ? String(parsed.jobId) === String(jobId) : true;
    const selected = matchesJob && Array.isArray(parsed?.selected)
      ? parsed.selected
      : (matchesJob && Array.isArray(parsed) ? parsed : []);

    if (matchesJob && selected.length) {
      await renderSummaryFromSelectedScenes(io, {
        jobId,
        userId,
        projectId,
        videoPath,
        videoFilename,
        transcriptItems,
        selectedScenes: selected,
        totalDuration,
        options,
        overlaySettings,
        workDir,
        processingMode,
      });
      return;
    }
  }

  await updateJob(io, userId, jobId, {
    progress: 0.3,
    error_message: `Analyze transcript for AI summary | chunks=${chunks.length}`,
  });

  for (let i = 0; i < chunks.length; i += 1) {
    const chunkIndex = i + 1;

    const items = chunks[i].map((it) => ({ startSec: it.startSec, endSec: it.endSec, text: it.text }));

    const progress = 0.3 + (0.4 * (i / Math.max(1, chunks.length)));
    await updateJob(io, userId, jobId, {
      progress,
      error_message: `Generate narration chunk ${chunkIndex}/${chunks.length}`,
    });

    const contextItems =
      i === 0 || overlapItems === 0
        ? []
        : chunks[i - 1].slice(Math.max(0, chunks[i - 1].length - overlapItems));
    const contextText = contextItems.length ? formatItemsAsSrt(contextItems) : '';

    // chunk bounds (we’ll clamp every segment into this)
    const minChunkStart = items.length ? items[0].startSec : 0;
    const maxChunkEnd = items.length ? items[items.length - 1].endSec : 0;

    const result = await analyzeStoryChunkWithBedrockMulti(
      items,
      storySoFar,
      chunkIndex,
      options.summaryMinSegSec,
      options.summaryMaxSegSec,
      contextText,
      lastEnd,
      segmentsPerChunk
    );

    let resolved = result;
    if (!resolved || !Array.isArray(resolved.segments) || resolved.segments.length === 0) {
      resolved = fallbackStorySegments(
        items,
        chunkIndex,
        options.summaryMinSegSec,
        options.summaryMaxSegSec,
        segmentsPerChunk
      );
    }

    if (!resolved || !Array.isArray(resolved.segments) || resolved.segments.length === 0) {
      await fs.writeFile(
        path.join(chunksDir, `chunk_${String(chunkIndex).padStart(2, '0')}_skip.json`),
        JSON.stringify({ reason: 'no_segments', result }, null, 2),
        'utf8'
      );
      continue;
    }

    debugChunks.push({ chunkIndex, ...resolved });

    await fs.writeFile(
      path.join(chunksDir, `chunk_${String(chunkIndex).padStart(2, '0')}_segments.json`),
      JSON.stringify(resolved, null, 2),
      'utf8'
    );

    // Update story memory once per chunk, after processing its segments
    const upd = String(resolved.storyUpdate || '').trim();
    if (upd) {
      storySoFar = `${storySoFar} ${upd}`.trim();
      if (storySoFar.length > options.storyMemoryChars) {
        storySoFar = storySoFar.slice(-options.storyMemoryChars);
      }
    }

    // Track last end to keep the next chunk's segments after previous ones
    const lastSeg = resolved.segments[resolved.segments.length - 1];
    if (lastSeg && Number.isFinite(Number(lastSeg.endSec))) {
      lastEnd = Number(lastSeg.endSec);
    }
  }

  await fs.writeFile(
    path.join(workDir, 'story_segments_debug.json'),
    JSON.stringify(debugChunks, null, 2),
    'utf8'
  );

  const candidates = debugChunks.flatMap((entry) => {
    const segs = Array.isArray(entry.segments) ? entry.segments : [];
    return segs.map((seg) => ({
      chunkIndex: entry.chunkIndex,
      startSec: seg.startSec,
      endSec: seg.endSec,
      storyText: seg.storyText,
    }));
  });

  if (!candidates.length) {
    throw new Error('No summary segments produced. Check story_chunks/*_skip.json and story_segments_debug.json.');
  }

  const suggested = maxSegments === Infinity ? candidates : candidates.slice(0, maxSegments);
  await fs.writeFile(
    candidatesPath,
    JSON.stringify({ jobId, candidates, suggested }, null, 2),
    'utf8'
  );

  if (options.summaryPlanOnly) {
    await updateJob(io, userId, jobId, {
      status: 'awaiting_selection',
      progress: 0.65,
      error_message: 'AI summary candidates ready. Select scenes to render.',
    });
    await updateProjectProgress(projectId, 'processing');

    if (io && userId) {
      io.to(`user:${userId}`).emit('summary:scenes_ready', {
        jobId,
        projectId,
        candidates,
        suggested,
        timestamp: new Date().toISOString(),
      });
    }
    return;
  }

  await renderSummaryFromSelectedScenes(io, {
    jobId,
    userId,
    projectId,
    videoPath,
    videoFilename,
    transcriptItems,
    selectedScenes: suggested,
    totalDuration,
    options,
    overlaySettings,
    workDir,
    processingMode,
  });
}

async function renderSummaryFromSelectedScenes(
  io,
  {
    jobId,
    userId,
    projectId,
    videoPath,
    videoFilename,
    transcriptItems,
    selectedScenes,
    totalDuration,
    options,
    overlaySettings,
    workDir,
    processingMode,
  }
) {
  if (!Array.isArray(selectedScenes) || selectedScenes.length === 0) {
    throw new Error('No selected scenes to render.');
  }

  await updateJob(io, userId, jobId, {
    progress: 0.75,
    error_message: `Rendering ${selectedScenes.length} selected scenes`,
  });

  const segmentsDir = path.join(workDir, 'story_segments');
  await fs.mkdir(segmentsDir, { recursive: true });

  const watermarkPath = resolveWatermarkPath(overlaySettings);
  const audioInfo = await probeAudioInfo(videoPath);
  const audioMode = pickAudioMode(audioInfo);

  const ordered = [...selectedScenes].sort(
    (a, b) => Number(a.startSec) - Number(b.startSec)
  );

  const finalSceneFiles = [];
  let lastEnd = -1;
  let globalSegIndex = 0;

  for (let i = 0; i < ordered.length; i += 1) {
    const seg = ordered[i];
    let start = Number(seg.startSec);
    let end = Number(seg.endSec);
    const storyText = String(seg.storyText || seg.story_text || '').trim();

    if (Number.isFinite(totalDuration) && totalDuration > 0) {
      start = clamp(start, 0, totalDuration);
      end = clamp(end, 0, totalDuration);
    }
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start + 0.5) continue;

    if (lastEnd >= 0 && start < lastEnd) {
      continue;
    }

    const clipDur = end - start;
    if (clipDur < 0.5) continue;

    globalSegIndex += 1;
    const segTag = String(globalSegIndex).padStart(4, '0');

    const overlayConfig = buildOverlayConfig(overlaySettings, watermarkPath);
    const { audioMapArgs, audioArgs, audioFilterArgs } = buildAudioArgs(audioMode, { forCut: true });
    const videoMapArgs = overlayConfig.useComplex ? ['-map', '[v]'] : ['-map', '0:v:0'];
    const mapArgs = [...videoMapArgs, ...audioMapArgs];

    const clipBase = path.join(segmentsDir, `seg_${segTag}_base.mp4`);
    await runCommand(FFMPEG, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-ss',
      start.toFixed(3),
      '-t',
      clipDur.toFixed(3),
      '-i',
      videoPath,
      ...overlayConfig.inputArgs,
      ...overlayConfig.filterArgs,
      ...mapArgs,
      ...audioFilterArgs,
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      ...audioArgs,
      ...overlayConfig.outputArgs,
      '-movflags',
      '+faststart',
      clipBase,
    ]);

    const rawTts = path.join(segmentsDir, `seg_${segTag}_tts_raw.wav`);
    const fitTts = path.join(segmentsDir, `seg_${segTag}_tts_fit.wav`);
    await ttsGenerateWav(storyText || 'A key moment unfolds.', rawTts, options.ttsVoice);
    await fitTtsToSegmentNoPad(rawTts, fitTts, clipDur, options.maxSpeedup, options.minSlowdown);

    const clipFinal = path.join(segmentsDir, `seg_${segTag}_final.mp4`);
    if (processingMode === 'ai_summary_hybrid') {
      await mixTtsOverOriginalDuck(clipBase, fitTts, clipFinal, options.duckVolume, options.ttsFadeSec);
    } else {
      await muxReplaceAudio(clipBase, fitTts, clipFinal);
    }

    finalSceneFiles.push(clipFinal);
    lastEnd = end;

    const ratio = (i + 1) / Math.max(1, ordered.length);
    await updateJob(io, userId, jobId, {
      progress: 0.75 + 0.2 * ratio,
      error_message: `Rendered ${i + 1}/${ordered.length} selected scenes`,
    });
  }

  if (!finalSceneFiles.length) {
    throw new Error('All selected scenes were invalid after clamping.');
  }

  await updateJob(io, userId, jobId, { progress: 0.95, error_message: 'Merging summary video' });

  const outputDir = path.join(workDir, 'result');
  await fs.mkdir(outputDir, { recursive: true });

  const outputFilename = makeOutputFilename(videoFilename, 0);
  const outputPath = path.join(outputDir, outputFilename);
  const tmpOutput = `${outputPath}.tmp_${Date.now()}.mp4`;

  if (finalSceneFiles.length === 1) {
    await fs.copyFile(finalSceneFiles[0], tmpOutput);
  } else {
    await concatClips(finalSceneFiles, tmpOutput, workDir, 'aac');
  }

  await fs.rename(tmpOutput, outputPath);

  const publicOutputPath = toPublicUrl(outputPath);
  const sizeBytes = await safeStatSize(outputPath);
  const durationSec = await probeDuration(outputPath);

  const outputId = uuidv4();
  await db.runAsync(
    `INSERT INTO output_videos
     (id, project_id, job_id, chunk_index, filename, file_path, duration_sec, size_bytes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [outputId, projectId, jobId, 0, outputFilename, outputPath, durationSec || null, sizeBytes || null]
  );

  await updateJob(io, userId, jobId, {
    status: 'completed',
    progress: 1.0,
    output_filename: outputFilename,
    output_path: publicOutputPath,
    error_message: null,
  });

  await updateProjectProgress(projectId, 'completed');

  if (io && userId) {
    const output = await db.getAsync('SELECT * FROM output_videos WHERE id = ?', [outputId]);
    io.to(`user:${userId}`).emit('output:created', {
      output,
      timestamp: new Date().toISOString(),
    });
  }
}


async function analyzeChunks(io, userId, jobId, projectId, chunks, options, totalDuration) {
  const all = [];

  const cacheRows = await db.allAsync(
    `SELECT chunk_index, segments_json
     FROM ai_chunk_results
     WHERE project_id = ?
     ORDER BY chunk_index ASC`,
    [projectId]
  );
  const cache = new Map();
  for (const row of cacheRows) cache.set(row.chunk_index, safeJson(row.segments_json) || []);

  const overlapItems = Math.max(0, options.contextOverlap || 0);

  for (let i = 0; i < chunks.length; i += 1) {
    const chunkIndex = i + 1;
    const items = chunks[i].map((it) => ({ startSec: it.startSec, endSec: it.endSec, text: it.text }));

    const contextItems =
      i === 0 || overlapItems === 0
        ? []
        : chunks[i - 1].slice(Math.max(0, chunks[i - 1].length - overlapItems));

    const contextText = contextItems.length ? formatItemsAsSrt(contextItems) : '';

    let segments = cache.get(chunkIndex) || [];
    if (!segments.length) {
      segments =
        (await analyzeWithBedrock(items, options, contextText, chunkIndex)) ||
        heuristicAnalyze(items, options);

      await db.runAsync(
        `INSERT INTO ai_chunk_results
         (id, project_id, user_id, chunk_index, chunk_input_json, context_text, segments_json, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(project_id, chunk_index) DO UPDATE SET
           chunk_input_json = excluded.chunk_input_json,
           context_text = excluded.context_text,
           segments_json = excluded.segments_json,
           updated_at = CURRENT_TIMESTAMP`,
        [
          uuidv4(),
          projectId,
          userId,
          chunkIndex,
          JSON.stringify(items),
          contextText,
          JSON.stringify(segments),
        ]
      );
    }

    const ratio = (i + 1) / chunks.length;
    const progress = 0.3 + 0.45 * ratio;
    await updateJob(io, userId, jobId, {
      progress,
      error_message: `AI analyzing chunk ${i + 1}/${chunks.length} (remaining ${chunks.length - (i + 1)})`,
    });

    // Validate/sanitize segments
    const minChunkStart = items.length ? items[0].startSec : 0;
    const maxChunkEnd = items.length ? items[items.length - 1].endSec : 0;

    for (const seg of segments) {
      let startSec = Number(seg.startSec ?? 0);
      let endSec = Number(seg.endSec ?? 0);

      // Clamp to chunk bounds (reduces hallucinated timestamps)
      if (
        Number.isFinite(minChunkStart) &&
        Number.isFinite(maxChunkEnd) &&
        maxChunkEnd > minChunkStart
      ) {
        startSec = clamp(startSec, minChunkStart, maxChunkEnd);
        endSec = clamp(endSec, minChunkStart, maxChunkEnd);
      }

      // Clamp to total duration
      if (Number.isFinite(totalDuration) && totalDuration > 0) {
        startSec = clamp(startSec, 0, totalDuration);
        endSec = clamp(endSec, 0, totalDuration);
      }

      if (!Number.isFinite(startSec) || !Number.isFinite(endSec)) continue;
      if (endSec <= startSec + 0.5) continue;

      all.push({
        startSec,
        endSec,
        score: Number(seg.score || 0),
        why: seg.why,
      });
    }
  }

  // ----------------------------
  // Adaptive threshold selection
  // ----------------------------
  const base = Number.isFinite(Number(options.scoreThreshold))
    ? Number(options.scoreThreshold)
    : 72;

  // 72 -> 68 -> 64 -> 60 -> 55 (or based on base)
  const thresholds = [
    base,
    Math.max(65, base - 4),
    Math.max(60, base - 8),
    Math.max(55, base - 12),
    55,
  ];
  const finalize = (picked) =>
    applyScenePadding(picked, options, totalDuration);

  // If strict threshold yields too few scenes, relax gradually.
  for (const t of thresholds) {
    const picked = selectBestNonOverlapping(all, { ...options, scoreThreshold: t });
    if (picked.length >= 3) return finalize(picked); // change 3 -> 2 if you want fewer required
  }

  // Still few: relax min gap a bit + lower threshold a bit more (keeps "best scenes", not whole movie)
  const relaxed = {
    ...options,
    scoreThreshold: Math.max(40, base - 20),
    minGapSec: Math.min(Number(options.minGapSec ?? 2.0), 0.5),
  };
  return finalize(selectBestNonOverlapping(all, relaxed));
}

function selectBestNonOverlapping(scenes, options) {
  const sorted = [...scenes].sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return a.startSec - b.startSec;
  });

  const chosen = [];
  let total = 0;

  const maxScenes =
    options.maxScenes === null || options.maxScenes === undefined ? Infinity : Number(options.maxScenes);
  const maxTotalSec =
    options.maxTotalSec === null || options.maxTotalSec === undefined ? Infinity : Number(options.maxTotalSec);

  for (const s of sorted) {
    const dur = s.endSec - s.startSec;
    if (dur <= 0.5) continue;
    if (s.score < (options.scoreThreshold ?? 0)) continue;

    const conflict = chosen.some(
      (c) => !(s.endSec + (options.minGapSec ?? 0) <= c.startSec || s.startSec >= c.endSec + (options.minGapSec ?? 0))
    );
    if (conflict) continue;

    if (Number.isFinite(maxScenes) && chosen.length >= maxScenes) break;
    if (Number.isFinite(maxTotalSec) && total + dur > maxTotalSec) continue;

    chosen.push(s);
    total += dur;
  }

  if (!chosen.length) return [];
  chosen.sort((a, b) => a.startSec - b.startSec);
  return chosen;
}

function applyScenePadding(scenes, options, totalDuration) {
  if (!Array.isArray(scenes) || scenes.length === 0) return scenes;

  const pad = Number(options.scenePaddingSec || 0);
  const minLen = Number(options.minSceneSec || 0);
  const maxLen = Number(options.maxSceneSec || 0);
  const gap = Number(options.minGapSec || 0);
  const total =
    Number.isFinite(totalDuration) && totalDuration > 0
      ? totalDuration
      : null;

  const ordered = [...scenes].sort((a, b) => a.startSec - b.startSec);
  const adjusted = [];
  let prevEnd = null;

  for (const scene of ordered) {
    let start = Number(scene.startSec);
    let end = Number(scene.endSec);
    if (!Number.isFinite(start) || !Number.isFinite(end)) continue;

    if (pad > 0) {
      start -= pad;
      end += pad;
    }

    if (total !== null) {
      start = clamp(start, 0, total);
      end = clamp(end, 0, total);
    }

    let len = end - start;
    if (minLen > 0 && len < minLen) {
      const need = minLen - len;
      let before = need / 2;
      let after = need - before;
      start -= before;
      end += after;
      if (total !== null) {
        if (start < 0) {
          end = clamp(end + Math.abs(start), 0, total);
          start = 0;
        }
        if (end > total) {
          const overflow = end - total;
          start = clamp(start - overflow, 0, total);
          end = total;
        }
      }
      len = end - start;
    }

    if (maxLen > 0 && len > maxLen) {
      const center = (start + end) / 2;
      start = center - maxLen / 2;
      end = center + maxLen / 2;
      if (total !== null) {
        if (start < 0) {
          end = clamp(end + Math.abs(start), 0, total);
          start = 0;
        }
        if (end > total) {
          const overflow = end - total;
          start = clamp(start - overflow, 0, total);
          end = total;
        }
      }
      len = end - start;
    }

    if (prevEnd !== null && start < prevEnd + gap) {
      const targetStart = prevEnd + gap;
      const targetEnd = targetStart + len;
      start = targetStart;
      end = targetEnd;
      if (total !== null && end > total) {
        end = total;
        start = Math.max(prevEnd + gap, end - len);
      }
    }

    if (end <= start + 0.5) continue;

    adjusted.push({
      ...scene,
      startSec: start,
      endSec: end,
    });
    prevEnd = end;
  }

  return adjusted;
}

function heuristicAnalyze(items, options) {
  const keywords = [
    'but', 'however', 'finally', 'important', 'secret', 'problem', 'solution',
    'amazing', 'wow', 'must', 'need', 'never', 'always', 'why', 'how',
  ];

  const minSec = Number(options.minSceneSec || 0);
  const maxSec = Number(options.maxSceneSec || 0);

  const scored = items.map((it) => {
    const text = String(it.text || '').toLowerCase();
    // Slightly less optimistic scoring
    let score = Math.min(95, Math.floor((text.length / 260) * 100));
    for (const k of keywords) if (text.includes(k)) score += 7;

    score = clamp(score, 15, 98);

    const s = Number(it.startSec || 0);
    const e = Number(it.endSec || s);
    let dur = Math.max(0.2, e - s);
    if (minSec > 0) dur = Math.max(dur, minSec);
    if (maxSec > 0) dur = Math.min(dur, maxSec);

    return { startSec: s, endSec: s + dur, score, why: 'High information density (heuristic)' };
  });

  return scored
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(1, options.segmentsPerChunk))
    .sort((a, b) => a.startSec - b.startSec);
}

async function analyzeWithBedrock(items, options, contextText, chunkIndex) {
  if (!hasBedrockConfig()) return null;

  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
  const modelId = process.env.BEDROCK_MODEL_ID || 'eu.anthropic.claude-sonnet-4-20250514-v1:0';
  const credentials = getAwsCredentialsFromEnv();

  const lengthRule =
    options.minSceneSec && options.maxSceneSec
      ? `- Each segment length must be between ${options.minSceneSec} and ${options.maxSceneSec} seconds.`
      : options.minSceneSec
        ? `- Each segment length must be at least ${options.minSceneSec} seconds.`
        : options.maxSceneSec
          ? `- Each segment length must be at most ${options.maxSceneSec} seconds.`
          : '';

  const prompt = `
You will receive a CHUNK of an SRT transcript. The video can be in ANY language.

Task: pick up to ${options.segmentsPerChunk} BEST scene segments from THIS chunk.

Rules:
- Do NOT translate the transcript. Evaluate content in the ORIGINAL language.
- Use ONLY timestamps that appear in this SRT chunk.
${lengthRule}
- Prefer: reveals, conflict, turning points, strong emotion, punchlines, key decisions.
- Avoid: filler, greetings, silence, repeated info.
- Return JSON only (no markdown).

Return JSON:
{
  "chunk_index": ${chunkIndex},
  "segments": [
    {
      "start_ts": "HH:MM:SS,mmm",
      "end_ts": "HH:MM:SS,mmm",
      "score": 0-100,
      "why": "short reason in the same language as transcript"
    }
  ]
}

Additional context from previous chunk (continuity only; DO NOT use its timestamps):
${contextText || '(none)'}

SRT CHUNK:
${formatItemsAsSrt(items)}
  `.trim();

  const client = new BedrockRuntimeClient(credentials ? { region, credentials } : { region });

  const body = {
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: Math.min(Number.isNaN(MAX_TOKENS_OUT) ? 4096 : MAX_TOKENS_OUT, 64000),
    temperature: 0.2,
    messages: [{ role: 'user', content: [{ type: 'text', text: prompt }] }],
  };

  const response = await client.send(
    new InvokeModelCommand({
      modelId,
      contentType: 'application/json',
      accept: 'application/json',
      body: JSON.stringify(body),
    })
  );

  const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'));
  const text =
    decoded?.content?.find?.((c) => c?.type === 'text')?.text ||
    decoded?.output_text ||
    '';

  const parsed = extractJsonObject(text);
  if (!parsed || typeof parsed !== 'object') return null;

  const out = Array.isArray(parsed?.segments) ? parsed.segments : [];
  return out
    .map((s) => {
      const startSec = coerceSegmentTime(s.startSec ?? s.start_ts ?? s.startTs ?? s.start);
      const endSec = coerceSegmentTime(s.endSec ?? s.end_ts ?? s.endTs ?? s.end);
      if (!Number.isFinite(startSec) || !Number.isFinite(endSec)) return null;
      if (endSec <= startSec + 0.25) return null;

      return {
        startSec,
        endSec,
        score: clamp(Number(s.score || 0), 0, 100),
        why: String(s.why || ''),
      };
    })
    .filter(Boolean);
}


async function analyzeStoryChunkWithBedrock(
  items,
  storySoFar,
  chunkIndex,
  summaryMinSec,
  summaryMaxSec,
  contextText,
  lastEndSec = -1 // NEW: helps model avoid earlier segments
) {
  if (!hasBedrockConfig()) return null;

  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
  const modelId = process.env.BEDROCK_MODEL_ID || 'eu.anthropic.claude-sonnet-4-20250514-v1:0';
  const credentials = getAwsCredentialsFromEnv();

  const minSec = Number.isFinite(Number(summaryMinSec)) ? Number(summaryMinSec) : DEFAULT_SUMMARY_MIN_SEG_SEC;
  const maxSec = Number.isFinite(Number(summaryMaxSec)) ? Number(summaryMaxSec) : DEFAULT_SUMMARY_MAX_SEG_SEC;

  const lastEndHint =
    Number.isFinite(Number(lastEndSec)) && Number(lastEndSec) >= 0
      ? `- IMPORTANT: Do not choose a segment that starts before LAST_END_SEC = ${Number(lastEndSec).toFixed(3)}.`
      : '';

  const prompt = `
You are turning dialog into a NEW narrated story. You will receive a CHUNK of an SRT transcript.

Return EXACTLY ONE segment from this chunk.

Rules:
- Use ONLY timestamps that appear in this SRT chunk.
- Segment length must be ${minSec}–${maxSec} seconds.
- Choose the MOST important story beat that advances the plot.
- Prefer earlier timestamps in the chunk to keep the story chronological.
${lastEndHint}
- Write story_text to FIT the segment duration:
  - target_words = round(segment_duration_sec * 2.35)
  - allowed range = target_words ± 10% (approx)
  - Keep it 1–2 sentences max, cinematic, story voice.
- CHUNK 1 story_text must begin with: "Once upon a time" OR "This story is about"
- CHUNK > 1 story_text must begin with: "Then" OR "But soon" OR "Meanwhile" OR "After that"
- Output JSON only. No extra text.

STORY SO FAR (continue it; do not repeat verbatim):
${storySoFar || '[none yet]'}

Additional context from previous chunk (continuity only; DO NOT use its timestamps):
${contextText || '(none)'}

Return JSON:
{
  "chunk_index": ${chunkIndex},
  "segment": {
    "start_ts": "HH:MM:SS,mmm",
    "end_ts": "HH:MM:SS,mmm",
    "story_text": "..."
  },
  "story_so_far_update": "1-2 sentences describing what the viewer now knows"
}

SRT CHUNK:
${formatItemsAsSrt(items)}
  `.trim();

  const client = new BedrockRuntimeClient(credentials ? { region, credentials } : { region });
  const body = {
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: Math.min(Number.isNaN(MAX_TOKENS_OUT) ? 4096 : MAX_TOKENS_OUT, 64000),
    temperature: 0.2,
    messages: [{ role: 'user', content: [{ type: 'text', text: prompt }] }],
  };

  const response = await client.send(
    new InvokeModelCommand({
      modelId,
      contentType: 'application/json',
      accept: 'application/json',
      body: JSON.stringify(body),
    })
  );

  const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'));
  const text =
    decoded?.content?.find?.((c) => c?.type === 'text')?.text ||
    decoded?.output_text ||
    '';

  const parsed = extractJsonObject(text);
  if (!parsed || typeof parsed !== 'object') return null;

  // Some models may return the segment at top-level by mistake
  const segment = (parsed.segment && typeof parsed.segment === 'object') ? parsed.segment : parsed;

  const startSec = coerceSegmentTime(
    segment.startSec ?? segment.start_ts ?? segment.startTs ?? segment.start
  );
  const endSec = coerceSegmentTime(
    segment.endSec ?? segment.end_ts ?? segment.endTs ?? segment.end
  );

  const storyText = String(segment.story_text || segment.storyText || parsed.story_text || '').trim();
  const storyUpdate = String(parsed.story_so_far_update || parsed.storySoFarUpdate || '').trim();

  if (!Number.isFinite(startSec) || !Number.isFinite(endSec) || !storyText) return null;
  if (endSec <= startSec + 0.25) return null;

  return { startSec, endSec, storyText, storyUpdate };
}


function fallbackStorySegments(items, chunkIndex, summaryMinSec, summaryMaxSec, segmentsPerChunk) {
  if (!items || items.length === 0) return null;
  const first = items[0];
  const last = items[items.length - 1];
  const minSec = Number.isFinite(Number(summaryMinSec)) ? Number(summaryMinSec) : DEFAULT_SUMMARY_MIN_SEG_SEC;
  const maxSec = Number.isFinite(Number(summaryMaxSec)) ? Number(summaryMaxSec) : DEFAULT_SUMMARY_MAX_SEG_SEC;
  const maxSegments =
    Number.isFinite(Number(segmentsPerChunk)) && Number(segmentsPerChunk) > 0
      ? Number(segmentsPerChunk)
      : 1;

  const maxEnd = Number(last.endSec || Number(first.startSec || 0));
  let start = Number(first.startSec || 0);
  let idx = 0;
  const segments = [];

  while (segments.length < maxSegments && start < maxEnd) {
    let end = start + Math.max(minSec, Math.min(maxSec, maxEnd - start));
    end = Math.min(end, maxEnd);
    if (end <= start + 0.25) break;

    while (idx < items.length - 1 && Number(items[idx].startSec) < start) {
      idx += 1;
    }
    let baseText = String(items[idx]?.text || '').trim();
    if (!baseText) baseText = 'A key moment unfolds.';
    if (baseText.length > 220) baseText = `${baseText.slice(0, 217)}...`;

    const isFirst = chunkIndex === 1 && segments.length === 0;
    const prefix = isFirst ? 'Once upon a time, ' : 'Then, ';
    const storyText = `${prefix}${baseText}`;

    segments.push({ startSec: start, endSec: end, storyText });
    start = end;
  }

  const storyUpdate = segments.length
    ? segments[segments.length - 1].storyText
    : '';

  return { segments, storyUpdate };
}

async function concatClips(clips, outputPath, workDir, audioMode) {
  const listPath = path.join(workDir, 'concat_list.txt');

  // Safer escaping (still best on Linux). If you target Windows, consider using filter_complex concat.
  const lines = clips.map((p) => `file '${p.replace(/\\/g, '/').replace(/'/g, "'\\''")}'`).join('\n');
  await fs.writeFile(listPath, lines, 'utf8');

  const { audioMapArgs, audioArgs } = buildAudioArgs(audioMode, { forCut: false });
  const mapArgs = ['-map', '0:v:0', ...audioMapArgs];

  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-fflags',
    '+genpts',
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    listPath,
    ...mapArgs,
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '20',
    '-pix_fmt',
    'yuv420p',
    ...audioArgs,
    '-movflags',
    '+faststart',
    outputPath,
  ]);
}

async function transcribeToSrt(wavPath, outSrtPath) {
  if (!WHISPER_BIN || !WHISPER_MODEL) {
    throw new Error('WHISPER_BIN and WHISPER_MODEL must be configured on backend');
  }
  const workDir = path.dirname(outSrtPath);
  const prefix = path.join(workDir, `transcript_${Date.now()}`);

  await runCommand(WHISPER_BIN, ['-m', WHISPER_MODEL, '-f', wavPath, '-osrt', '-of', prefix]);

  const generated = `${prefix}.srt`;
  await fs.rename(generated, outSrtPath);
}

async function probeDuration(filePath) {
  try {
    const { stdout } = await runCommand(FFPROBE, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=nk=1:nw=1',
      filePath,
    ]);
    const val = parseFloat(String(stdout || '').trim());
    return Number.isFinite(val) ? val : null;
  } catch (_) {
    return null;
  }
}

async function hasAudioStream(filePath) {
  try {
    const { stdout } = await runCommand(FFPROBE, [
      '-v',
      'error',
      '-select_streams',
      'a',
      '-show_entries',
      'stream=codec_type',
      '-of',
      'csv=p=0',
      filePath,
    ]);
    return String(stdout || '').trim().length > 0;
  } catch (_) {
    return false;
  }
}

async function probeAudioInfo(filePath) {
  try {
    const { stdout } = await runCommand(FFPROBE, [
      '-v',
      'error',
      '-select_streams',
      'a:0',
      '-show_entries',
      'stream=codec_name,channels',
      '-of',
      'json',
      filePath,
    ]);
    const parsed = JSON.parse(String(stdout || '{}'));
    const stream = Array.isArray(parsed.streams) ? parsed.streams[0] : null;
    if (!stream) return { hasAudio: false };
    return {
      hasAudio: true,
      codec: String(stream.codec_name || '').toLowerCase(),
      channels: Number(stream.channels || 0),
    };
  } catch (_) {
    const hasAudio = await hasAudioStream(filePath);
    return { hasAudio };
  }
}

async function safeStatSize(filePath) {
  try {
    const stat = await fs.stat(filePath);
    return stat.size;
  } catch (_) {
    return null;
  }
}

// -------------------- SRT parsing/building (improved) --------------------

function parseSrt(raw) {
  if (!raw) return [];
  const blocks = String(raw).replace(/\r/g, '').split(/\n\s*\n/);
  const out = [];

  const timingRe =
    /^(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})/;

  for (const block of blocks) {
    const lines = block
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l.length > 0);

    if (lines.length < 2) continue;

    const timingLine = lines.find((l) => timingRe.test(l));
    if (!timingLine) continue;

    const m = timingLine.match(timingRe);
    if (!m) continue;

    const startSec = srtTsToSeconds(m[1].trim());
    const endSec = srtTsToSeconds(m[2].trim());

    if (!Number.isFinite(startSec) || !Number.isFinite(endSec)) continue;
    if (endSec <= startSec) continue;

    const textLines = lines
      .filter((l) => l !== timingLine && !/^\d+$/.test(l))
      .map((l) => stripSrtTags(l));

    const text = textLines.join(' ').replace(/\s+/g, ' ').trim();
    if (!text) continue;

    out.push({ startSec, endSec, text });
  }

  // Ensure sorted
  out.sort((a, b) => a.startSec - b.startSec);
  return out;
}

function srtTsToSeconds(ts) {
  const m = String(ts).match(/(\d+):(\d+):(\d+)[,.](\d+)/);
  if (!m) return null;
  const h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  const s = parseInt(m[3], 10);
  const ms = parseInt(String(m[4]).padEnd(3, '0').slice(0, 3), 10);
  return h * 3600 + min * 60 + s + ms / 1000;
}

function stripSrtTags(text) {
  if (!text) return '';
  return String(text)
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

function chunkByItemCount(items, chunkSize) {
  const safe = Math.max(1, chunkSize || 1);
  const chunks = [];
  for (let i = 0; i < items.length; i += safe) chunks.push(items.slice(i, i + safe));
  return chunks;
}

function estimateTokensForItem(item) {
  // Safer estimate than /4; use /3 and clamp
  const start = secondsToSrt(item.startSec || 0);
  const end = secondsToSrt(item.endSec || 0);
  const text = String(item.text || '');
  const payload = `${start} --> ${end}\n${text}`;
  return Math.max(5, Math.ceil(payload.length / 3));
}

function chunkByTokenBudget(items, maxTokens, overheadTokens) {
  const budgetRaw = Number(maxTokens) || 0;
  const overhead = Number(overheadTokens) || 0;
  const budget = Math.max(1000, budgetRaw - overhead);

  const chunks = [];
  let current = [];
  let tokenCount = 0;

  // Hard secondary guard (chars) to avoid edge tokenization blow-ups
  const HARD_CHAR_BUDGET = Math.max(8000, budget * 4); // heuristic

  let charCount = 0;

  for (const item of items) {
    const cost = estimateTokensForItem(item);
    const textLen = String(item.text || '').length;

    if (current.length > 0 && (tokenCount + cost > budget || charCount + textLen > HARD_CHAR_BUDGET)) {
      chunks.push(current);
      current = [];
      tokenCount = 0;
      charCount = 0;
    }

    current.push(item);
    tokenCount += cost;
    charCount += textLen;
  }

  if (current.length > 0) chunks.push(current);
  return chunks;
}

function makeOutputFilename(originalFilename, chunkIndex) {
  const ext = path.extname(originalFilename || '') || '.mp4';
  const base = path.basename(originalFilename || 'output', ext).replace(/[^a-zA-Z0-9-_]/g, '_');
  const index = String(chunkIndex + 1).padStart(3, '0');
  return `${base}_${index}${ext}`;
}

function normalizeLimit(value) {
  if (value === null || value === undefined) return null;
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) return null;
  return num;
}

function clamp(num, min, max) {
  return Math.max(min, Math.min(max, num));
}

function toPublicUrl(filePath) {
  if (!filePath) return null;
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) return filePath;

  let rel = filePath;
  if (filePath.startsWith('/uploads/')) {
    rel = filePath;
  } else if (path.isAbsolute(filePath) && filePath.startsWith(UPLOAD_ROOT)) {
    rel = path.join('/uploads', path.relative(UPLOAD_ROOT, filePath)).split(path.sep).join('/');
  }

  if (!rel.startsWith('/')) rel = `/${rel}`;
  if (PUBLIC_BASE_URL) return `${PUBLIC_BASE_URL}${rel}`;
  return rel;
}

function hasBedrockConfig() {
  return Boolean(process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION);
}

function getAwsCredentialsFromEnv() {
  const accessKeyId = process.env.AWS_ACCESS_KEY_ID || process.env.AWS_ACCESSKEY_ID;
  const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
  const sessionToken = process.env.AWS_SESSION_TOKEN;
  if (!accessKeyId || !secretAccessKey) return null;
  return { accessKeyId, secretAccessKey, sessionToken };
}

function extractJsonObject(raw) {
  if (!raw) return null;

  const text = String(raw).trim();
  if (!text) return null;

  // -----------------------------
  // 1) direct JSON (fast path)
  // -----------------------------
  try {
    const obj = JSON.parse(text);
    return obj && typeof obj === 'object' ? obj : null;
  } catch (_) { }

  // -----------------------------------------
  // 2) fenced code blocks: ```json ... ```
  // -----------------------------------------
  // Prefer json fenced blocks; fall back to any fenced block.
  const fences = [];
  const fenceRe = /```(?:json|JSON)?\s*([\s\S]*?)```/g;
  let fm;
  while ((fm = fenceRe.exec(text)) !== null) {
    if (fm[1]) fences.push(fm[1].trim());
  }
  for (const candidate of fences) {
    // candidate itself may still contain commentary before/after JSON; try balanced extraction
    const extracted = extractFirstBalancedJson(candidate);
    if (extracted) return extracted;
    try {
      const obj = JSON.parse(candidate);
      if (obj && typeof obj === 'object') return obj;
    } catch (_) { }
  }

  // -----------------------------------------------------
  // 3) “best effort” balanced { ... } or [ ... ] extraction
  // -----------------------------------------------------
  return extractFirstBalancedJson(text);
}

/**
 * Extract the first balanced JSON object/array from a string and JSON.parse it.
 * Handles:
 * - leading/trailing commentary
 * - multiple JSON objects
 * - braces inside quoted strings
 */
function extractFirstBalancedJson(text) {
  if (!text) return null;
  const s = String(text);

  // Find first '{' or '['
  const firstObj = s.indexOf('{');
  const firstArr = s.indexOf('[');
  let start = -1;

  if (firstObj === -1 && firstArr === -1) return null;
  if (firstObj === -1) start = firstArr;
  else if (firstArr === -1) start = firstObj;
  else start = Math.min(firstObj, firstArr);

  const openChar = s[start];
  const closeChar = openChar === '{' ? '}' : ']';

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = start; i < s.length; i += 1) {
    const ch = s[i];

    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch === '\\') {
        escape = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      continue;
    }

    if (ch === openChar) depth += 1;
    if (ch === closeChar) depth -= 1;

    if (depth === 0) {
      const slice = s.slice(start, i + 1).trim();
      try {
        const obj = JSON.parse(slice);
        return obj && typeof obj === 'object' ? obj : null;
      } catch (_) {
        return null;
      }
    }
  }

  return null;
}


function formatItemsAsSrt(items) {
  return items
    .map((it, idx) => {
      const start = secondsToSrt(it.startSec || 0);
      const end = secondsToSrt(it.endSec || 0);
      const text = String(it.text || '').trim();
      return `${idx + 1}\n${start} --> ${end}\n${text}`;
    })
    .join('\n\n');
}

function secondsToSrt(sec) {
  const t = Math.max(0, Number(sec) || 0);
  const msTotal = Math.round(t * 1000);
  const h = Math.floor(msTotal / 3600000);
  const m = Math.floor((msTotal % 3600000) / 60000);
  const s = Math.floor((msTotal % 60000) / 1000);
  const ms = msTotal % 1000;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')},${String(ms).padStart(3, '0')}`;
}

function escapeFilterPath(p) {
  return String(p || '')
    .replace(/\\/g, '\\\\')
    .replace(/:/g, '\\:')
    .replace(/'/g, "\\'")
    .replace(/ /g, '\\ ');
}

// More standards-compliant merge SRT
function buildMergedSrt(transcriptItems, clips) {
  if (!Array.isArray(transcriptItems) || !Array.isArray(clips)) return '';
  let index = 1;
  let timelineOffset = 0;
  const blocks = [];

  for (const clip of clips) {
    const clipStart = Number(clip.startSec || 0);
    const clipEnd = Number(clip.endSec || 0);
    const clipDur = Number(clip.durationSec || clipEnd - clipStart);
    if (!Number.isFinite(clipStart) || !Number.isFinite(clipEnd)) continue;

    for (const item of transcriptItems) {
      if (item.endSec <= clipStart || item.startSec >= clipEnd) continue;
      const start = Math.max(item.startSec, clipStart) - clipStart + timelineOffset;
      const end = Math.min(item.endSec, clipEnd) - clipStart + timelineOffset;
      if (end <= start) continue;

      blocks.push(`${index}\n${secondsToSrt(start)} --> ${secondsToSrt(end)}\n${item.text}`);
      index += 1;
    }

    timelineOffset += Number.isFinite(clipDur) ? clipDur : 0;
  }

  return blocks.join('\n\n').trim();
}

async function writeMergedSrt(transcriptItems, clips, outPath) {
  const content = buildMergedSrt(transcriptItems, clips);
  if (!content) return false;
  await fs.writeFile(outPath, `${content}\n`, 'utf8');
  return true;
}

function buildSceneSrt(items, startSec, endSec) {
  const blocks = [];
  let index = 1;
  for (const item of items) {
    if (item.endSec <= startSec || item.startSec >= endSec) continue;
    const st = Math.max(item.startSec, startSec) - startSec;
    const en = Math.min(item.endSec, endSec) - startSec;
    if (en <= st) continue;
    blocks.push(`${index}\n${secondsToSrt(st)} --> ${secondsToSrt(en)}\n${item.text}`);
    index += 1;
  }
  return blocks.join('\n\n').trim();
}

async function writeSceneTranscripts(transcriptItems, scenes, workDir) {
  try {
    const clipsDir = path.join(workDir, 'clips');
    await fs.mkdir(clipsDir, { recursive: true });

    const sceneSummaries = [];
    for (let i = 0; i < scenes.length; i += 1) {
      const scene = scenes[i];
      const srt = buildSceneSrt(transcriptItems, scene.startSec, scene.endSec);
      const srtFilename = `scene_${String(i + 1).padStart(3, '0')}.srt`;
      const srtPath = path.join(clipsDir, srtFilename);
      if (srt) await fs.writeFile(srtPath, `${srt}\n`, 'utf8');

      const text = srt
        ? srt
          .split('\n')
          .filter((line) => line && !line.includes('-->') && !/^\d+$/.test(line))
          .join(' ')
          .replace(/\s+/g, ' ')
          .trim()
        : '';

      sceneSummaries.push({
        index: i + 1,
        startSec: scene.startSec,
        endSec: scene.endSec,
        score: scene.score,
        why: scene.why || null,
        srt: srtFilename,
        text,
      });
    }

    const jsonPath = path.join(workDir, 'scene_texts.json');
    await fs.writeFile(jsonPath, JSON.stringify(sceneSummaries, null, 2), 'utf8');
  } catch (err) {
    console.warn('[worker] Failed to write scene transcripts:', err);
  }
}

async function burnSubtitles(inputPath, srtPath, outputPath, audioMode) {
  if (!hasSubtitlesFilter()) return false;

  const escaped = escapeFilterPath(srtPath);
  const style = 'Fontsize=18\\,Outline=1\\,Shadow=0\\,Alignment=2';
  const vf = `subtitles=filename=${escaped}:force_style=${style}`;

  const { audioMapArgs, audioArgs } = buildAudioArgs(audioMode, { forCut: false });
  const mapArgs = ['-map', '0:v:0', ...audioMapArgs];

  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    inputPath,
    '-vf',
    vf,
    ...mapArgs,
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '20',
    '-pix_fmt',
    'yuv420p',
    ...audioArgs,
    '-movflags',
    '+faststart',
    outputPath,
  ]);

  return true;
}

function resolveWatermarkPath(settings) {
  if (!settings?.watermarkEnabled) return null;
  const envPath = process.env.WATERMARK_PATH;
  if (envPath && fsSync.existsSync(envPath)) return envPath;
  const defaultPath = path.resolve(__dirname, '..', 'assets', 'watermark.png');
  if (fsSync.existsSync(defaultPath)) return defaultPath;
  return null;
}

function loadFfmpegFiltersOnce() {
  if (ffmpegFiltersCache) return ffmpegFiltersCache;
  try {
    const result = spawnSync(FFMPEG, ['-hide_banner', '-filters'], { encoding: 'utf8' });
    if (result.error) {
      ffmpegFiltersCache = '';
      return ffmpegFiltersCache;
    }
    ffmpegFiltersCache = `${result.stdout || ''}\n${result.stderr || ''}`;
    return ffmpegFiltersCache;
  } catch (_) {
    ffmpegFiltersCache = '';
    return ffmpegFiltersCache;
  }
}

function hasDrawtextFilter() {
  if (drawtextAvailable !== null) return drawtextAvailable;
  const out = loadFfmpegFiltersOnce();
  drawtextAvailable = out.includes(' drawtext ') || out.includes('drawtext');
  return drawtextAvailable;
}

function hasSubtitlesFilter() {
  if (subtitlesAvailable !== null) return subtitlesAvailable;
  const out = loadFfmpegFiltersOnce();
  subtitlesAvailable = out.includes(' subtitles ') || out.includes('subtitles');
  return subtitlesAvailable;
}

function resolveFontFile() {
  const envPath = process.env.FFMPEG_FONT_FILE;
  const candidates = [
    envPath,
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  ].filter(Boolean);
  for (const c of candidates) if (c && fsSync.existsSync(c)) return c;
  return null;
}

function escapeDrawtext(text) {
  return String(text || '')
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/:/g, '\\:');
}

function parseResolution(value) {
  const m = String(value || '').match(/^(\d{2,5})x(\d{2,5})$/i);
  if (!m) return { width: DEFAULT_CANVAS_WIDTH, height: DEFAULT_CANVAS_HEIGHT };
  const width = parseInt(m[1], 10);
  const height = parseInt(m[2], 10);
  if (!Number.isFinite(width) || !Number.isFinite(height)) return { width: DEFAULT_CANVAS_WIDTH, height: DEFAULT_CANVAS_HEIGHT };
  return { width, height };
}

function getRandomTextPosition(width, height) {
  const scaleX = width / DEFAULT_CANVAS_WIDTH;
  const scaleY = height / DEFAULT_CANVAS_HEIGHT;
  const minX = Math.round(TEXT_MARGIN_X * scaleX);
  const minY = Math.round(TEXT_MARGIN_Y * scaleY);
  const maxX = Math.round(TEXT_MAX_X * scaleX);
  const maxY = Math.round(TEXT_MAX_Y * scaleY);
  const safeMaxX = Math.max(minX + 1, maxX);
  const safeMaxY = Math.max(minY + 1, maxY);
  const x = minX + Math.floor(Math.random() * (safeMaxX - minX));
  const y = minY + Math.floor(Math.random() * (safeMaxY - minY));
  return { x, y };
}

function getFixedTextPosition(width, height) {
  return { x: Math.round(width / 2), y: Math.round(height - 300) };
}

function getOverlayExpression(position) {
  switch (position) {
    case 'top_left':
      return `${WATERMARK_MARGIN}:${WATERMARK_MARGIN}`;
    case 'top_right':
      return `W-w-${WATERMARK_MARGIN}:${WATERMARK_MARGIN}`;
    case 'bottom_left':
      return `${WATERMARK_MARGIN}:H-h-${WATERMARK_MARGIN}`;
    case 'bottom_right':
    default:
      return `W-w-${WATERMARK_MARGIN}:H-h-${WATERMARK_MARGIN}`;
  }
}

function buildOverlayConfig(settings, watermarkPath) {
  const { width, height } = parseResolution(settings.outputResolution);
  const flipMode = settings.flipMode === 'hflip' || settings.flipMode === 'vflip' ? settings.flipMode : 'none';

  const canDrawText = hasDrawtextFilter();
  const hasText = canDrawText && settings.channelName && settings.channelName.length > 0;

  const useWatermark = Boolean(settings.watermarkEnabled && watermarkPath);
  const fontFile = resolveFontFile();
  const fontArg = fontFile ? `fontfile=${escapeDrawtext(fontFile)}:` : '';
  const text = escapeDrawtext(settings.channelName || '');

  const textPos = settings.textRandomPosition ? getRandomTextPosition(width, height) : getFixedTextPosition(width, height);

  const baseFilters = [
    'setpts=PTS-STARTPTS',
    ...(flipMode !== 'none' ? [flipMode] : []),
    `scale=${width}:${height}:force_original_aspect_ratio=decrease`,
    `pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2`,
    'setsar=1',
  ];

  if (useWatermark) {
    const overlayExpr = getOverlayExpression(settings.watermarkPosition);
    const graph = [
      `[0:v]${baseFilters.join(',')},format=rgba[v0]`,
      `[1:v]scale=${DEFAULT_WATERMARK_WIDTH}:-2,format=rgba,colorchannelmixer=aa=${settings.watermarkAlpha}[wm]`,
      `[v0][wm]overlay=${overlayExpr}:shortest=1[v1]`,
      hasText
        ? `[v1]drawtext=${fontArg}text='${text}':x=${textPos.x}:y=${textPos.y}:fontsize=36:fontcolor=white:borderw=3:bordercolor=black@0.6[v2]`
        : `[v1]null[v2]`,
      `[v2]format=yuv420p[v]`,
    ].join(';');

    return {
      useComplex: true,
      inputArgs: ['-loop', '1', '-i', watermarkPath],
      filterArgs: ['-filter_complex', graph],
      outputArgs: ['-shortest'],
    };
  }

  const vfParts = [...baseFilters, 'format=yuv420p'];
  if (hasText) {
    vfParts.push(
      `drawtext=${fontArg}text='${text}':x=${textPos.x}:y=${textPos.y}:fontsize=36:fontcolor=white:borderw=3:bordercolor=black@0.6`
    );
  }

  return {
    useComplex: false,
    inputArgs: [],
    filterArgs: ['-vf', vfParts.join(',')],
    outputArgs: [],
  };
}

function resolveSayBinary() {
  const explicit = String(process.env.TTS_BIN || '').trim();
  if (explicit) return explicit;
  if (process.platform !== 'darwin') return null;
  const result = spawnSync('which', ['say'], { encoding: 'utf8' });
  if (result.status !== 0) return null;
  const bin = String(result.stdout || '').trim();
  return bin || null;
}

async function getKokoroTts() {
  if (kokoroInstance) return kokoroInstance;
  if (kokoroInitPromise) return kokoroInitPromise;

  kokoroInitPromise = (async () => {
    const mod = await import('kokoro-js');
    if (!mod || !mod.KokoroTTS) {
      throw new Error('kokoro-js is not available');
    }
    const tts = await mod.KokoroTTS.from_pretrained(KOKORO_MODEL_ID, {
      dtype: KOKORO_DTYPE,
    });
    return tts;
  })();

  kokoroInstance = await kokoroInitPromise;
  return kokoroInstance;
}

function resolveTtsVoiceName(voiceId) {
  const raw = String(voiceId || '').trim();
  if (!raw) return DEFAULT_TTS_VOICE;
  if (raw.startsWith('af_')) return 'Samantha';
  if (raw.startsWith('am_')) return 'Alex';
  if (raw.startsWith('bf_')) return 'Victoria';
  if (raw.startsWith('bm_')) return 'Daniel';
  return raw;
}

function sanitizeTtsText(text) {
  return String(text || '').replace(/\s+/g, ' ').trim();
}

async function ttsGenerateWav(text, outWavPath, voice) {
  const clean = sanitizeTtsText(text);
  if (!clean) throw new Error('Empty narration text');

  if (TTS_ENGINE === 'kokoro' || TTS_ENGINE === 'kokoro_strict') {
    try {
      const tts = await getKokoroTts();
      const voiceId = String(voice || 'af_heart');
      const audio = await tts.generate(clean, { voice: voiceId });
      const tmpPath = outWavPath.replace(/\.wav$/i, `_kokoro_${Date.now()}.wav`);
      await audio.save(tmpPath);

      await runCommand(FFMPEG, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        tmpPath,
        '-ar',
        '48000',
        '-ac',
        '2',
        '-c:a',
        'pcm_s16le',
        outWavPath,
      ]);
      await fs.unlink(tmpPath).catch(() => { });
      return;
    } catch (err) {
      if (TTS_ENGINE === 'kokoro_strict') throw err;
      console.warn('[worker] kokoro TTS failed, fallback to say:', err?.message || err);
    }
  }

  const sayBin = resolveSayBinary();
  if (!sayBin) {
    throw new Error('TTS not configured. Set TTS_ENGINE=kokoro or TTS_BIN for macOS "say".');
  }
  const base = outWavPath.replace(/\.wav$/i, '');
  const aiffPath = `${base}.aiff`;
  const resolvedVoice = resolveTtsVoiceName(voice);
  await runCommand(sayBin, ['-v', resolvedVoice, '-o', aiffPath, clean]);
  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    aiffPath,
    '-ar',
    '48000',
    '-ac',
    '2',
    '-c:a',
    'pcm_s16le',
    outWavPath,
  ]);
  await fs.unlink(aiffPath).catch(() => { });
}

async function trimAndFadeWav(inWav, outWav, maxSec, fadeSec) {
  const dur = Math.max(0.2, Number(maxSec) || 0.2);
  const fade = Math.max(0.03, Math.min(Number(fadeSec) || DEFAULT_TTS_FADE_SEC, dur / 6.0));
  const fadeOutStart = Math.max(0, dur - fade);

  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    inWav,
    '-filter:a',
    `atrim=0:${dur.toFixed(3)},afade=t=in:st=0:d=${fade.toFixed(3)},afade=t=out:st=${fadeOutStart.toFixed(3)}:d=${fade.toFixed(3)}`,
    '-ar',
    '48000',
    '-ac',
    '2',
    '-c:a',
    'pcm_s16le',
    outWav,
  ]);

  return probeDuration(outWav);
}

async function muxReplaceAudio(videoPath, audioPath, outPath) {
  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    videoPath,
    '-i',
    audioPath,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-b:a',
    '192k',
    '-shortest',
    '-movflags',
    '+faststart',
    outPath,
  ]);
}

function atempoChain(factor) {
  const parts = [];
  let f = Number(factor) || 1.0;
  while (f > 2.0) {
    parts.push('atempo=2.0');
    f /= 2.0;
  }
  while (f < 0.5) {
    parts.push('atempo=0.5');
    f /= 0.5;
  }
  parts.push(`atempo=${f.toFixed(6)}`);
  return parts.join(',');
}

async function fitTtsToSegmentNoPad(inWav, outWav, targetSec, maxSpeedup, minSlowdown) {
  const inDur = (await probeDuration(inWav)) || 0;
  const target = Math.max(0.5, Number(targetSec) || 0.5);
  if (inDur <= 0.1) {
    await runCommand(FFMPEG, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=48000:cl=stereo',
      '-t',
      '0.50',
      '-c:a',
      'pcm_s16le',
      outWav,
    ]);
    return;
  }

  const ratio = inDur / target;
  if (ratio > 1.0) {
    const speed = Math.min(ratio, Math.max(1.0, maxSpeedup));
    const chain = atempoChain(speed);
    await runCommand(FFMPEG, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      inWav,
      '-filter:a',
      `${chain},atrim=0:${target.toFixed(3)}`,
      '-ar',
      '48000',
      '-ac',
      '2',
      '-c:a',
      'pcm_s16le',
      outWav,
    ]);
    return;
  }

  const slow = Math.max(ratio, Math.max(0.5, minSlowdown));
  const chain = atempoChain(slow);
  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    inWav,
    '-filter:a',
    chain,
    '-ar',
    '48000',
    '-ac',
    '2',
    '-c:a',
    'pcm_s16le',
    outWav,
  ]);
}

async function mixTtsOverOriginalDuck(clipAv, ttsWav, outPath, duckVolume, fadeSec) {
  const hasAudio = await hasAudioStream(clipAv);
  if (!hasAudio) {
    await muxReplaceAudio(clipAv, ttsWav, outPath);
    return;
  }

  const ttsDur = (await probeDuration(ttsWav)) || 0;
  if (ttsDur <= 0.05) {
    await fs.copyFile(clipAv, outPath);
    return;
  }

  const fade = Math.min(Number(fadeSec) || DEFAULT_TTS_FADE_SEC, Math.max(0.03, ttsDur / 6.0));
  const fadeOutStart = Math.max(0, ttsDur - fade);
  const duck = Number.isFinite(Number(duckVolume)) ? Number(duckVolume) : DEFAULT_DUCK_VOLUME;

  const filter =
    `[0:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,` +
    `volume='if(lt(t,${ttsDur.toFixed(3)}),${duck.toFixed(4)},1.0)'[bg];` +
    `[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,` +
    `atrim=0:${ttsDur.toFixed(3)},asetpts=PTS-STARTPTS,` +
    `afade=t=in:st=0:d=${fade.toFixed(3)},` +
    `afade=t=out:st=${fadeOutStart.toFixed(3)}:d=${fade.toFixed(3)}[tts];` +
    `[bg][tts]amix=inputs=2:duration=first:dropout_transition=0[aout]`;

  await runCommand(FFMPEG, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    clipAv,
    '-i',
    ttsWav,
    '-filter_complex',
    filter,
    '-map',
    '0:v:0',
    '-map',
    '[aout]',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-b:a',
    '192k',
    '-movflags',
    '+faststart',
    outPath,
  ]);
}

function coerceSegmentTime(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const raw = String(value).trim();
  if (!raw) return null;
  const asNum = Number(raw);
  if (Number.isFinite(asNum)) return asNum;
  const asTs = srtTsToSeconds(raw);
  return Number.isFinite(asTs) ? asTs : null;
}

// Improved: audio policy for stability.
// - For cuts/concat, prefer AAC encode unless explicitly allowed and codec is already AAC.
function pickAudioMode(audioInfo) {
  if (!audioInfo || !audioInfo.hasAudio) return 'none';

  // If user explicitly wants copy AND codec likely safe, allow it.
  if (PREFER_AUDIO_COPY && audioInfo.codec === 'aac') return 'copy';

  // default stable mode: encode
  return 'aac';
}

function buildAudioArgs(audioMode, { forCut } = {}) {
  const audioMapArgs = [];
  const audioFilterArgs = [];

  if (audioMode !== 'none') audioMapArgs.push('-map', '0:a:0?');

  if (audioMode === 'none') return { audioMapArgs, audioArgs: ['-an'], audioFilterArgs };

  if (audioMode === 'copy') return { audioMapArgs, audioArgs: ['-c:a', 'copy'], audioFilterArgs };

  // aac encode
  if (forCut) audioFilterArgs.push('-af', 'asetpts=PTS-STARTPTS');
  return {
    audioMapArgs,
    audioArgs: ['-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-ar', '48000'],
    audioFilterArgs,
  };
}

// -------------------- DB updates --------------------

async function updateJob(io, userId, jobId, fields) {
  const updates = [];
  const params = [];

  if (fields.status !== undefined) {
    updates.push('status = ?');
    params.push(fields.status);

    if (fields.status === 'running') {
      updates.push('started_at = CURRENT_TIMESTAMP');
    } else if (fields.status === 'completed' || fields.status === 'failed') {
      updates.push('completed_at = CURRENT_TIMESTAMP');
    }
  }
  if (fields.progress !== undefined) {
    updates.push('progress = ?');
    params.push(fields.progress);
  }
  if (fields.error_message !== undefined) {
    updates.push('error_message = ?');
    params.push(fields.error_message);
  }
  if (fields.output_filename !== undefined) {
    updates.push('output_filename = ?');
    params.push(fields.output_filename);
  }
  if (fields.output_path !== undefined) {
    updates.push('output_path = ?');
    params.push(fields.output_path);
  }
  if (!updates.length) return null;

  params.push(jobId);

  await db.runAsync(`UPDATE queue_jobs SET ${updates.join(', ')} WHERE id = ?`, params);

  const updatedJob = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [jobId]);

  if (io && userId && updatedJob) {
    io.to(`user:${userId}`).emit('job:updated', { job: updatedJob, timestamp: new Date().toISOString() });

    if (updatedJob.status === 'completed') {
      io.to(`user:${userId}`).emit('job:completed', { job: updatedJob, timestamp: new Date().toISOString() });
    } else if (updatedJob.status === 'failed') {
      io.to(`user:${userId}`).emit('job:failed', { job: updatedJob, timestamp: new Date().toISOString() });
    }
  }

  return updatedJob;
}

async function updateProjectProgress(projectId, statusOverride) {
  const stats = await db.getAsync(
    `SELECT
       COUNT(*) as total_jobs,
       SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending_jobs,
       SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running_jobs,
       SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_jobs,
       SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_jobs,
       AVG(progress) as avg_progress
     FROM queue_jobs
     WHERE project_id = ?`,
    [projectId]
  );

  const total = stats?.total_jobs || 0;
  const completed = stats?.completed_jobs || 0;
  const failed = stats?.failed_jobs || 0;
  const runningJobs = stats?.running_jobs || 0;
  const pending = stats?.pending_jobs || 0;
  const avgProgress = stats?.avg_progress ?? 0;

  let projectStatus = statusOverride || 'pending';
  if (total > 0 && completed === total) {
    projectStatus = 'completed';
  } else if (total > 0 && failed > 0 && completed + failed === total) {
    projectStatus = 'failed';
  } else if (runningJobs > 0 || completed > 0 || failed > 0) {
    projectStatus = 'processing';
  } else if (pending === total) {
    projectStatus = 'pending';
  }

  await db.runAsync(
    `UPDATE projects
     SET status = ?, completed_chunks = ?, failed_chunks = ?, progress = ?, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?`,
    [projectStatus, completed, failed, avgProgress || 0, projectId]
  );
}

function safeJson(val) {
  if (!val) return null;
  try {
    return JSON.parse(val);
  } catch (_) {
    return null;
  }
}

// -------------------- Process helpers --------------------

async function runCommand(cmd, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';
    let killedByTimeout = false;

    const t =
      COMMAND_TIMEOUT_MS > 0
        ? setTimeout(() => {
          killedByTimeout = true;
          try {
            child.kill('SIGKILL');
          } catch (_) { }
        }, COMMAND_TIMEOUT_MS)
        : null;

    child.stdout.on('data', (d) => (stdout += d.toString()));
    child.stderr.on('data', (d) => (stderr += d.toString()));
    child.on('error', (err) => {
      if (t) clearTimeout(t);
      reject(err);
    });
    child.on('close', (code) => {
      if (t) clearTimeout(t);
      if (killedByTimeout) {
        return reject(new Error(`Command timed out: ${cmd} ${args.join(' ')}`));
      }
      if (code === 0) return resolve({ stdout, stderr });
      return reject(
        new Error(`Command failed (${code}): ${cmd} ${args.join(' ')}\n${stderr || stdout}`)
      );
    });
  });
}

async function analyzeStoryChunkWithBedrockMulti(
  items,
  storySoFar,
  chunkIndex,
  summaryMinSec,
  summaryMaxSec,
  contextText,
  lastEndSec = -1,
  segmentsPerChunk = 1
) {
  if (!hasBedrockConfig()) return null;

  const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
  const modelId = process.env.BEDROCK_MODEL_ID || 'eu.anthropic.claude-sonnet-4-20250514-v1:0';
  const credentials = getAwsCredentialsFromEnv();

  const minSec = Number.isFinite(Number(summaryMinSec)) ? Number(summaryMinSec) : DEFAULT_SUMMARY_MIN_SEG_SEC;
  const maxSec = Number.isFinite(Number(summaryMaxSec)) ? Number(summaryMaxSec) : DEFAULT_SUMMARY_MAX_SEG_SEC;

  const lastEndHint =
    Number.isFinite(Number(lastEndSec)) && Number(lastEndSec) >= 0
      ? `- IMPORTANT: The first segment MUST start at or after LAST_END_SEC = ${Number(lastEndSec).toFixed(3)}.`
      : '';

  const prompt = `
You are turning dialog into a NEW narrated story. You will receive a CHUNK of an SRT transcript.

Task: Produce up to ${segmentsPerChunk} narrated segments from THIS chunk (chronological).

Rules:
- Use ONLY timestamps that appear in THIS SRT chunk.
- Produce at most ${segmentsPerChunk} segments.
- Segments must be chronological and non-overlapping.
- Each segment length must be ${minSec}–${maxSec} seconds.
- Prefer full coverage of the chunk (start near the beginning, continue forward).
${lastEndHint}
- Write story_text to FIT each segment duration:
  - target_words = round(segment_duration_sec * 2.35)
  - allowed range = target_words ± 10% (approx)
  - Keep it 1–2 sentences max, cinematic, story voice.
- The FIRST segment of CHUNK 1 must begin with: "Once upon a time" OR "This story is about"
- The FIRST segment of CHUNK > 1 must begin with: "Then" OR "But soon" OR "Meanwhile" OR "After that"
- For later segments within the same chunk, you may start with "Then/Meanwhile/After that/But soon" as needed.
- Output JSON only. No markdown.

STORY SO FAR (continue it; do not repeat verbatim):
${storySoFar || '[none yet]'}

Additional context from previous chunk (continuity only; DO NOT use its timestamps):
${contextText || '(none)'}

Return JSON:
{
  "chunk_index": ${chunkIndex},
  "segments": [
    {
      "start_ts": "HH:MM:SS,mmm",
      "end_ts": "HH:MM:SS,mmm",
      "story_text": "..."
    }
  ],
  "story_so_far_update": "1-2 sentences describing what the viewer now knows after this chunk"
}

SRT CHUNK:
${formatItemsAsSrt(items)}
  `.trim();

  const client = new BedrockRuntimeClient(credentials ? { region, credentials } : { region });
  const body = {
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: Math.min(Number.isNaN(MAX_TOKENS_OUT) ? 4096 : MAX_TOKENS_OUT, 64000),
    temperature: 0.2,
    messages: [{ role: 'user', content: [{ type: 'text', text: prompt }] }],
  };

  const response = await client.send(
    new InvokeModelCommand({
      modelId,
      contentType: 'application/json',
      accept: 'application/json',
      body: JSON.stringify(body),
    })
  );

  const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'));
  const text =
    decoded?.content?.find?.((c) => c?.type === 'text')?.text ||
    decoded?.output_text ||
    '';

  const parsed = extractJsonObject(text);
  if (!parsed || typeof parsed !== 'object') return null;

  const segments = Array.isArray(parsed.segments) ? parsed.segments : [];
  const storyUpdate = String(parsed.story_so_far_update || parsed.storySoFarUpdate || '').trim();

  const normalized = segments
    .map((seg) => {
      const startSec = coerceSegmentTime(seg.startSec ?? seg.start_ts ?? seg.startTs ?? seg.start);
      const endSec = coerceSegmentTime(seg.endSec ?? seg.end_ts ?? seg.endTs ?? seg.end);
      const storyText = String(seg.story_text || seg.storyText || '').trim();
      if (!Number.isFinite(startSec) || !Number.isFinite(endSec) || !storyText) return null;
      if (endSec <= startSec + 0.25) return null;
      return { startSec, endSec, storyText };
    })
    .filter(Boolean)
    .sort((a, b) => a.startSec - b.startSec);

  const limited =
    Number.isFinite(Number(segmentsPerChunk)) && Number(segmentsPerChunk) > 0
      ? normalized.slice(0, Number(segmentsPerChunk))
      : normalized;

  return { segments: limited, storyUpdate };
}

async function exists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch (_) {
    return false;
  }
}

module.exports = {
  startQueueWorker,
};
