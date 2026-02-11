const express = require('express');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs/promises');
const multer = require('multer');

const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const UPLOAD_ROOT = path.resolve(UPLOAD_DIR);
const CHUNK_DIR = path.join(UPLOAD_ROOT, 'chunks');
const MAX_CHUNK_MB = parseInt(process.env.UPLOAD_CHUNK_MB || '25', 10);

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_CHUNK_MB * 1024 * 1024 },
});

async function ensureDir(dirPath) {
    await fs.mkdir(dirPath, { recursive: true });
}

async function readMeta(uploadId) {
    try {
        const metaPath = path.join(CHUNK_DIR, uploadId, 'meta.json');
        const raw = await fs.readFile(metaPath, 'utf8');
        return JSON.parse(raw);
    } catch (_) {
        return null;
    }
}

async function writeMeta(uploadId, meta) {
    const dir = path.join(CHUNK_DIR, uploadId);
    await ensureDir(dir);
    await fs.writeFile(
        path.join(dir, 'meta.json'),
        JSON.stringify(meta, null, 2),
        'utf8'
    );
}

async function mergeChunks(uploadId, meta, finalPath) {
    await ensureDir(path.dirname(finalPath));
    const out = await fs.open(finalPath, 'w');
    try {
        for (let i = 0; i < meta.totalParts; i += 1) {
            const partPath = path.join(CHUNK_DIR, uploadId, `part_${i}`);
            const data = await fs.readFile(partPath);
            await out.write(data);
        }
    } finally {
        await out.close();
    }
}

// Init chunked upload
router.post('/init', authenticateToken, async (req, res) => {
    try {
        const { filename, sizeBytes, totalParts, chunkSize } = req.body || {};
        if (!filename || !totalParts) {
            return res.status(400).json({ error: 'filename and totalParts are required' });
        }

        const uploadId = uuidv4();
        const ext = path.extname(filename) || '.mp4';
        const finalName = `${uploadId}${ext}`;

        const meta = {
            uploadId,
            userId: req.user.id,
            originalName: filename,
            finalName,
            sizeBytes: sizeBytes ? Number(sizeBytes) : null,
            totalParts: Number(totalParts),
            chunkSize: chunkSize ? Number(chunkSize) : null,
            createdAt: new Date().toISOString(),
        };

        await writeMeta(uploadId, meta);
        return res.json({ uploadId, finalName, totalParts: meta.totalParts });
    } catch (error) {
        console.error('Upload init error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

// Upload a single chunk part
router.post('/part', authenticateToken, upload.single('chunk'), async (req, res) => {
    try {
        const { uploadId, partIndex, totalParts } = req.body || {};
        if (!uploadId || partIndex === undefined) {
            return res.status(400).json({ error: 'uploadId and partIndex are required' });
        }

        const meta = await readMeta(uploadId);
        if (!meta) {
            return res.status(404).json({ error: 'Upload session not found' });
        }
        if (meta.userId !== req.user.id) {
            return res.status(403).json({ error: 'Unauthorized upload session' });
        }

        const idx = Number(partIndex);
        const expectedTotal = Number(totalParts || meta.totalParts);
        if (Number.isNaN(idx) || idx < 0 || idx >= expectedTotal) {
            return res.status(400).json({ error: 'Invalid partIndex' });
        }

        if (!req.file || !req.file.buffer) {
            return res.status(400).json({ error: 'chunk file is required' });
        }

        const dir = path.join(CHUNK_DIR, uploadId);
        await ensureDir(dir);
        const partPath = path.join(dir, `part_${idx}`);
        await fs.writeFile(partPath, req.file.buffer);

        return res.json({ ok: true, partIndex: idx });
    } catch (error) {
        console.error('Upload part error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

// Complete upload and register video
router.post('/complete', authenticateToken, async (req, res) => {
    try {
        const { uploadId, title, durationSec, resolution } = req.body || {};
        if (!uploadId) {
            return res.status(400).json({ error: 'uploadId is required' });
        }

        const meta = await readMeta(uploadId);
        if (!meta) {
            return res.status(404).json({ error: 'Upload session not found' });
        }
        if (meta.userId !== req.user.id) {
            return res.status(403).json({ error: 'Unauthorized upload session' });
        }

        const finalPath = path.join(UPLOAD_ROOT, meta.finalName);
        const missing = [];
        for (let i = 0; i < meta.totalParts; i += 1) {
            const partPath = path.join(CHUNK_DIR, uploadId, `part_${i}`);
            try {
                await fs.access(partPath);
            } catch (_) {
                missing.push(i);
            }
        }

        if (missing.length > 0) {
            return res.status(400).json({
                error: 'Missing parts',
                missing,
            });
        }

        await mergeChunks(uploadId, meta, finalPath);
        const stat = await fs.stat(finalPath);

        // Insert video row
        const videoId = uuidv4();
        const finalTitle = (title && String(title).trim()) || meta.originalName;

        await db.runAsync(
            `INSERT INTO videos (id, user_id, title, filename, file_path, duration_sec, resolution, size_bytes)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                videoId,
                req.user.id,
                finalTitle,
                meta.originalName,
                finalPath,
                durationSec ? parseFloat(durationSec) : null,
                resolution || null,
                stat.size,
            ]
        );

        // Cleanup chunk directory
        await fs.rm(path.join(CHUNK_DIR, uploadId), { recursive: true, force: true });

        return res.status(201).json({
            video: {
                id: videoId,
                title: finalTitle,
                filename: meta.originalName,
                size_bytes: stat.size,
                duration_sec: durationSec ? parseFloat(durationSec) : null,
                resolution: resolution || null,
                file_path: finalPath,
            },
        });
    } catch (error) {
        console.error('Upload complete error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
