const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');
const fs = require('fs').promises;
const path = require('path');

const router = express.Router();

// Register a new output video (called after split video is created)
router.post('/', authenticateToken, async (req, res) => {
    try {
        const { projectId, jobId, chunkIndex, filename, filePath, durationSec, sizeBytes } = req.body;

        if (!projectId || !jobId || chunkIndex === undefined) {
            return res.status(400).json({ error: 'projectId, jobId, and chunkIndex are required' });
        }

        // Verify project belongs to user and get associated video filename
        const project = await db.getAsync(
            `SELECT p.id, v.filename as video_filename
             FROM projects p
             JOIN videos v ON p.video_id = v.id
             WHERE p.id = ? AND p.user_id = ?`,
            [projectId, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        // If filename not provided, generate a deterministic one: <originalName>_NNN.ext
        let finalFilename = filename;
        if (!finalFilename) {
            const orig = project.video_filename || 'output';
            const ext = path.extname(orig) || '.mp4';
            const base = path.basename(orig, path.extname(orig)).replace(/[^a-zA-Z0-9-_]/g, '_');
            const index = String(chunkIndex + 1).padStart(3, '0');
            finalFilename = `${base}_${index}${ext}`;
        }

        const outputId = uuidv4();

        await db.runAsync(
            `INSERT INTO output_videos (id, project_id, job_id, chunk_index, filename, file_path, duration_sec, size_bytes)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [outputId, projectId, jobId, chunkIndex, finalFilename, filePath || null, durationSec || null, sizeBytes || null]
        );

        const output = await db.getAsync('SELECT * FROM output_videos WHERE id = ?', [outputId]);

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('output:created', {
                output,
                timestamp: new Date().toISOString()
            });
        }

        res.status(201).json({ output });
    } catch (error) {
        console.error('Create output error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get all outputs for a project
router.get('/:projectId', authenticateToken, async (req, res) => {
    try {
        // Verify project belongs to user
        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.projectId, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const outputs = await db.allAsync(
            `SELECT * FROM output_videos 
             WHERE project_id = ? 
             ORDER BY chunk_index ASC`,
            [req.params.projectId]
        );

        res.json({ outputs });
    } catch (error) {
        console.error('Get outputs error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Delete a specific output video
router.delete('/:id', authenticateToken, async (req, res) => {
    try {
        // Get output and verify ownership via project
        const output = await db.getAsync(
            `SELECT ov.*, p.user_id 
             FROM output_videos ov
             JOIN projects p ON ov.project_id = p.id
             WHERE ov.id = ?`,
            [req.params.id]
        );

        if (!output) {
            return res.status(404).json({ error: 'Output not found' });
        }

        if (output.user_id !== req.user.id) {
            return res.status(403).json({ error: 'Unauthorized' });
        }

        // Delete file from filesystem if path exists
        if (output.file_path) {
            try {
                await fs.unlink(output.file_path);
                console.log(`Deleted output file: ${output.file_path}`);
            } catch (err) {
                console.warn(`Could not delete file ${output.file_path}:`, err.message);
                // Continue with database deletion even if file deletion fails
            }
        }

        // Delete from database
        await db.runAsync('DELETE FROM output_videos WHERE id = ?', [req.params.id]);

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${output.user_id}`).emit('output:deleted', {
                outputId: req.params.id,
                projectId: output.project_id,
                timestamp: new Date().toISOString()
            });
        }

        res.json({ message: 'Output deleted successfully' });
    } catch (error) {
        console.error('Delete output error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
