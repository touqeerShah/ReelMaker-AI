const express = require('express');
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');
const multer = require('multer');
const os = require('os');
const path = require('path');
const fs = require('fs/promises');
const { spawn } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
const upload = multer({
    dest: path.join(os.tmpdir(), 'reelmaker-ai-transcribe'),
});

function clamp(num, min, max) {
    return Math.max(min, Math.min(max, num));
}

function heuristicAnalyze(items, minSceneSec, maxSceneSec, segmentsPerChunk) {
    const keywords = [
        'but', 'however', 'finally', 'important', 'secret', 'problem', 'solution',
        'amazing', 'wow', 'must', 'need', 'never', 'always', 'why', 'how',
    ];

    const scored = items.map((it) => {
        const text = (it.text || '').toString().toLowerCase();
        let score = Math.min(100, Math.floor((text.length / 220) * 100));
        for (const k of keywords) {
            if (text.includes(k)) score += 8;
        }
        score = clamp(score, 15, 98);

        const s = Number(it.startSec || 0);
        const e = Number(it.endSec || s + minSceneSec);
        const dur = clamp(e - s, minSceneSec, maxSceneSec);

        return {
            startSec: s,
            endSec: s + dur,
            score,
            why: 'High information density',
        };
    });

    return scored
        .sort((a, b) => b.score - a.score)
        .slice(0, Math.max(1, segmentsPerChunk))
        .sort((a, b) => a.startSec - b.startSec);
}

function extractJsonObject(raw) {
    if (!raw) return null;
    const trimmed = String(raw).trim();
    try {
        return JSON.parse(trimmed);
    } catch (_) {
        // Continue with best-effort extraction below.
    }

    const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fenced && fenced[1]) {
        try {
            return JSON.parse(fenced[1].trim());
        } catch (_) {
            // Continue.
        }
    }

    const firstBrace = trimmed.indexOf('{');
    const lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
        const candidate = trimmed.slice(firstBrace, lastBrace + 1);
        try {
            return JSON.parse(candidate);
        } catch (_) {
            return null;
        }
    }
    return null;
}

function hasBedrockConfig() {
    return Boolean(process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION);
}

function maxTokensOut() {
    const requested = parseInt(process.env.BEDROCK_MAX_TOKENS_OUT || '4096', 10);
    const cap = 64000; // Claude Sonnet 4 max output tokens
    if (Number.isNaN(requested)) return 4096;
    return Math.min(requested, cap);
}

function getAwsCredentialsFromEnv() {
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID || process.env.AWS_ACCESSKEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
    const sessionToken = process.env.AWS_SESSION_TOKEN;
    if (!accessKeyId || !secretAccessKey) return null;
    return { accessKeyId, secretAccessKey, sessionToken };
}

function runCommand(cmd, args = []) {
    return new Promise((resolve, reject) => {
        const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
        let stderr = '';
        let stdout = '';
        child.stdout.on('data', (d) => { stdout += d.toString(); });
        child.stderr.on('data', (d) => { stderr += d.toString(); });
        child.on('error', reject);
        child.on('close', (code) => {
            if (code === 0) return resolve({ stdout, stderr });
            reject(new Error(`Command failed (${code}): ${stderr || stdout}`));
        });
    });
}

async function safeUnlink(filePath) {
    try {
        await fs.unlink(filePath);
    } catch (_) {
        // Ignore cleanup errors.
    }
}

async function analyzeWithBedrock(items, minSceneSec, maxSceneSec, segmentsPerChunk, contextText = '') {
    if (!hasBedrockConfig()) return null;

    const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION;
    const modelId = process.env.BEDROCK_MODEL_ID || 'eu.anthropic.claude-sonnet-4-20250514-v1:0';
    const credentials = getAwsCredentialsFromEnv();

    const prompt = `
You are selecting best short video scenes from transcript chunk items.
Rules:
- Use ONLY provided item timestamps.
- Each segment length between ${minSceneSec} and ${maxSceneSec} seconds.
- Return up to ${segmentsPerChunk} segments.
- Return strict JSON: {"segments":[{"startSec":number,"endSec":number,"score":0-100,"why":"..."}]}

Additional context from previous chunk (for continuity only, do NOT use its timestamps):
${contextText || '(none)'}

Items for this chunk:
${JSON.stringify(items)}
`.trim();

    const client = new BedrockRuntimeClient(
        credentials ? { region, credentials } : { region }
    );
    const body = {
        anthropic_version: 'bedrock-2023-05-31',
        max_tokens: maxTokensOut(),
        temperature: 0.2,
        messages: [
            {
                role: 'user',
                content: [{ type: 'text', text: prompt }],
            },
        ],
    };

    const response = await client.send(new InvokeModelCommand({
        modelId,
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify(body),
    }));

    const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'));
    const text = decoded?.content?.find?.((c) => c?.type === 'text')?.text || decoded?.output_text || '';
    const parsed = extractJsonObject(text);
    if (!parsed) return null;

    try {
        const out = Array.isArray(parsed?.segments) ? parsed.segments : [];
        return out.map((s) => ({
            startSec: Number(s.startSec || 0),
            endSec: Number(s.endSec || 0),
            score: clamp(Number(s.score || 0), 0, 100),
            why: String(s.why || ''),
        }));
    } catch (_) {
        return null;
    }
}

router.get('/best-scenes/chunks/:projectId', authenticateToken, async (req, res) => {
    try {
        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.projectId, req.user.id]
        );
        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const rows = await db.allAsync(
            `SELECT chunk_index, chunk_input_json, context_text, segments_json, updated_at
             FROM ai_chunk_results
             WHERE project_id = ?
             ORDER BY chunk_index ASC`,
            [req.params.projectId]
        );

        return res.json({
            chunks: rows.map((r) => ({
                chunkIndex: r.chunk_index,
                chunkInput: JSON.parse(r.chunk_input_json || '[]'),
                contextText: r.context_text || '',
                segments: JSON.parse(r.segments_json || '[]'),
                updatedAt: r.updated_at,
            })),
        });
    } catch (error) {
        console.error('Get AI chunk cache error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

router.post('/best-scenes/chunks', authenticateToken, async (req, res) => {
    try {
        const {
            projectId,
            chunkIndex,
            chunkInput = [],
            contextText = '',
            segments = [],
        } = req.body || {};

        if (!projectId || chunkIndex === undefined) {
            return res.status(400).json({ error: 'projectId and chunkIndex are required' });
        }

        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [projectId, req.user.id]
        );
        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

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
                req.user.id,
                Number(chunkIndex),
                JSON.stringify(chunkInput),
                String(contextText || ''),
                JSON.stringify(segments),
            ]
        );

        return res.json({ ok: true });
    } catch (error) {
        console.error('Save AI chunk cache error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

// Transcribe extracted WAV audio to SRT using whisper-cli (backend helper)
router.post('/transcribe-audio', authenticateToken, upload.single('audio'), async (req, res) => {
    const inputPath = req.file?.path;
    const whisperBin = process.env.WHISPER_BIN || '';
    const whisperModel = process.env.WHISPER_MODEL || '';

    if (!inputPath) {
        return res.status(400).json({ error: 'audio file is required' });
    }

    if (!whisperBin || !whisperModel) {
        await safeUnlink(inputPath);
        return res.status(400).json({
            error: 'WHISPER_BIN and WHISPER_MODEL must be configured on backend',
        });
    }

    const workDir = path.dirname(inputPath);
    const prefix = path.join(workDir, `transcript_${Date.now()}`);
    const srtPath = `${prefix}.srt`;

    try {
        await runCommand(whisperBin, [
            '-m', whisperModel,
            '-f', inputPath,
            '-osrt',
            '-of', prefix,
        ]);

        const srt = await fs.readFile(srtPath, 'utf8');
        await safeUnlink(inputPath);
        await safeUnlink(srtPath);

        return res.json({ srt });
    } catch (error) {
        await safeUnlink(inputPath);
        await safeUnlink(srtPath);
        console.error('Audio transcription error:', error);
        return res.status(500).json({
            error: 'Transcription failed',
            details: error.message,
        });
    }
});

// Analyze one transcript chunk via LLM (or heuristic fallback)
router.post('/best-scenes/analyze', authenticateToken, async (req, res) => {
    try {
        print("best-scenes/analyze")
        const {
            chunkIndex = 0,
            items = [],
            contextText = '',
            minSceneSec = 20,
            maxSceneSec = 55,
            segmentsPerChunk = 1,
        } = req.body || {};

        if (!Array.isArray(items) || items.length === 0) {
            return res.status(400).json({ error: 'items[] is required' });
        }

        let llmSegments = null;
        try {
            llmSegments = await analyzeWithBedrock(
                items,
                Number(minSceneSec),
                Number(maxSceneSec),
                Number(segmentsPerChunk),
                String(contextText || '')
            );
        } catch (llmError) {
            console.warn('Bedrock analyze failed, using heuristic fallback:', llmError?.message || llmError);
        }

        const segments = llmSegments && llmSegments.length > 0
            ? llmSegments
            : heuristicAnalyze(
                items,
                Number(minSceneSec),
                Number(maxSceneSec),
                Number(segmentsPerChunk)
            );

        return res.json({
            chunkIndex: Number(chunkIndex),
            segments,
        });
    } catch (error) {
        console.error('Analyze AI best-scenes chunk error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
