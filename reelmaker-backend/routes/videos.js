const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');
const upload = require('../middleware/upload');

const router = express.Router();

// Create video metadata (no file upload - video stays on device)
router.post('/metadata', authenticateToken, async (req, res) => {
    try {
        const {
            title,
            durationSec,
            resolution,
            localPath,
            segmentDuration,
            overlayDuration,
            logoPosition,
            watermarkEnabled,
            watermarkAlpha
        } = req.body;

        if (!title) {
            return res.status(400).json({ error: 'Title is required' });
        }

        const videoId = uuidv4();

        await db.runAsync(
            `INSERT INTO videos (
                id, user_id, title, filename, file_path, duration_sec, resolution, size_bytes,
                segment_duration, overlay_duration, logo_position, watermark_enabled, watermark_alpha
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                videoId,
                req.user.id,
                title,
                title, // Use title as filename since no actual file upload
                localPath || null, // Store local device path if provided
                durationSec ? parseFloat(durationSec) : null,
                resolution || null,
                0, // No file size since video stays on device
                segmentDuration ? parseInt(segmentDuration) : null,
                overlayDuration ? parseFloat(overlayDuration) : null,
                logoPosition || 'bottom_right',
                watermarkEnabled !== undefined ? (watermarkEnabled ? 1 : 0) : 1,
                watermarkAlpha ? parseFloat(watermarkAlpha) : 0.55
            ]
        );

        res.status(201).json({
            video: {
                id: videoId,
                title,
                duration_sec: durationSec ? parseFloat(durationSec) : null,
                resolution: resolution || null,
                local_path: localPath || null,
                settings: {
                    segment_duration: segmentDuration ? parseInt(segmentDuration) : null,
                    overlay_duration: overlayDuration ? parseFloat(overlayDuration) : null,
                    logo_position: logoPosition || 'bottom_right',
                    watermark_enabled: watermarkEnabled !== undefined ? watermarkEnabled : true,
                    watermark_alpha: watermarkAlpha ? parseFloat(watermarkAlpha) : 0.55
                }
            }
        });
    } catch (error) {
        console.error('Video metadata creation error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Upload video
router.post('/upload', authenticateToken, upload.single('video'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'No video file uploaded' });
        }

        const { title, durationSec, resolution } = req.body;
        const videoId = uuidv4();

        await db.runAsync(
            `INSERT INTO videos (id, user_id, title, filename, file_path, duration_sec, resolution, size_bytes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                videoId,
                req.user.id,
                title || null,
                req.file.originalname,
                req.file.path,
                durationSec ? parseFloat(durationSec) : null,
                resolution || null,
                req.file.size
            ]
        );

        res.status(201).json({
            video: {
                id: videoId,
                title: title || null,
                filename: req.file.originalname,
                size_bytes: req.file.size,
                duration_sec: durationSec ? parseFloat(durationSec) : null,
                resolution: resolution || null
            }
        });
    } catch (error) {
        console.error('Video upload error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get all videos for current user
router.get('/', authenticateToken, async (req, res) => {
    try {
        const videos = await db.allAsync(
            `SELECT id, title, filename, duration_sec, resolution, size_bytes, created_at
       FROM videos
       WHERE user_id = ?
       ORDER BY created_at DESC`,
            [req.user.id]
        );

        res.json({ videos });
    } catch (error) {
        console.error('Get videos error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get specific video
router.get('/:id', authenticateToken, async (req, res) => {
    try {
        const video = await db.getAsync(
            `SELECT id, title, filename, file_path, duration_sec, resolution, size_bytes, created_at
       FROM videos
       WHERE id = ? AND user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (!video) {
            return res.status(404).json({ error: 'Video not found' });
        }

        res.json({ video });
    } catch (error) {
        console.error('Get video error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Delete video
router.delete('/:id', authenticateToken, async (req, res) => {
    try {
        const result = await db.runAsync(
            'DELETE FROM videos WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (result.changes === 0) {
            return res.status(404).json({ error: 'Video not found' });
        }

        res.json({ message: 'Video deleted successfully' });
    } catch (error) {
        console.error('Delete video error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
