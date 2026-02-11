const express = require('express');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs').promises;
const path = require('path');
const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const UPLOAD_ROOT = path.resolve(UPLOAD_DIR);

function toPublicUrl(req, filePath) {
    if (!filePath) return null;
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        return filePath;
    }

    let rel = filePath;
    if (filePath.startsWith('/uploads/')) {
        rel = filePath;
    } else if (path.isAbsolute(filePath) && filePath.startsWith(UPLOAD_ROOT)) {
        rel = path.join('/uploads', path.relative(UPLOAD_ROOT, filePath))
            .split(path.sep)
            .join('/');
    }

    if (!rel.startsWith('/')) rel = `/${rel}`;
    const baseUrl = (process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`)
        .replace(/\/+$/, '');
    return `${baseUrl}${rel}`;
}

// Create a new project (optionally with jobs)
router.post('/', authenticateToken, async (req, res) => {
    try {
        const { videoId, title, totalChunks, settings, jobs } = req.body;
        console.log('Create project request:', req.body);
        // totalChunks and videoId are required; title is optional and will default to the video's filename
        if (!videoId || !totalChunks) {
            return res.status(400).json({ error: 'videoId and totalChunks are required' });
        }

        // Serialize settings if provided
        const settingsJson = settings ? JSON.stringify(settings) : null;

        // Verify video belongs to user and get filename to default the project title
        const video = await db.getAsync(
            'SELECT id, filename FROM videos WHERE id = ? AND user_id = ?',
            [videoId, req.user.id]
        );

        if (!video) {
            return res.status(404).json({ error: 'Video not found' });
        }

        // Default title to filename (without extension) when not provided
        const defaultTitle = video.filename ? video.filename.replace(/\.[^/.]+$/, '') : 'Untitled Project';
        const finalTitle = title && title.trim().length > 0 ? title : defaultTitle;

        const projectId = uuidv4();

        // Start transaction by using serialize
        await new Promise((resolve, reject) => {
            db.serialize(async () => {
                try {
                    // Create project
                    await db.runAsync(
                        `INSERT INTO projects (id, user_id, video_id, title, total_chunks, status, progress, settings_json, version)
                   VALUES (?, ?, ?, ?, ?, 'pending', 0.0, ?, 1)`,
                        [projectId, req.user.id, videoId, finalTitle, totalChunks, settingsJson]
                    );

                    // Create jobs if provided
                    const createdJobs = [];
                    if (jobs && Array.isArray(jobs) && jobs.length > 0) {
                        for (const job of jobs) {
                            const jobId = job.id || uuidv4();

                            await db.runAsync(
                                `INSERT INTO queue_jobs (id, project_id, video_id, chunk_index, status, progress)
                                 VALUES (?, ?, ?, ?, 'pending', 0.0)`,
                                [jobId, projectId, videoId, job.chunk_index || 0]
                            );

                            const createdJob = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [jobId]);
                            createdJobs.push(createdJob);
                        }
                    }

                    resolve({ createdJobs });
                } catch (err) {
                    reject(err);
                }
            });
        });

        const project = await db.getAsync('SELECT * FROM projects WHERE id = ?', [projectId]);

        // Get all jobs for this project
        const projectJobs = await db.allAsync(
            'SELECT * FROM queue_jobs WHERE project_id = ? ORDER BY chunk_index',
            [projectId]
        );

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('project:created', {
                project,
                jobs: projectJobs,
                timestamp: new Date().toISOString()
            });
        }

        res.status(201).json({ project, jobs: projectJobs });
    } catch (error) {
        console.error('Create project error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get all projects for current user
router.get('/', authenticateToken, async (req, res) => {
    try {
        const { status } = req.query;

        let query = `
      SELECT p.*, v.title as video_title, v.duration_sec, v.resolution,
             (
               SELECT ov.file_path
               FROM output_videos ov
               WHERE ov.project_id = p.id
               ORDER BY ov.chunk_index ASC
               LIMIT 1
             ) as thumbnail_path
      FROM projects p
      JOIN videos v ON p.video_id = v.id
      WHERE p.user_id = ?
    `;
        const params = [req.user.id];

        if (status) {
            query += ' AND p.status = ?';
            params.push(status);
        }

        query += ' ORDER BY p.created_at DESC';

        const projects = await db.allAsync(query, params);
        const decorated = projects.map((p) => ({
            ...p,
            thumbnail_path: toPublicUrl(req, p.thumbnail_path),
        }));

        res.json({ projects: decorated });
    } catch (error) {
        console.error('Get projects error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get summary candidates for a project (AI summary planning)
router.get('/:id/summary-candidates', authenticateToken, async (req, res) => {
    try {
        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const workDir = path.join(UPLOAD_ROOT, 'projects', req.params.id);
        const candidatesPath = path.join(workDir, 'summary_candidates.json');
        const raw = await fs.readFile(candidatesPath, 'utf8').catch(() => '');
        if (!raw) {
            return res.status(404).json({ error: 'No summary candidates found' });
        }

        const parsed = JSON.parse(raw);
        res.json(parsed);
    } catch (error) {
        console.error('Get summary candidates error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Submit selected summary scenes to render
router.post('/:id/summary-selection', authenticateToken, async (req, res) => {
    try {
        const { jobId, selected } = req.body;
        if (!jobId) {
            return res.status(400).json({ error: 'jobId is required' });
        }
        if (!Array.isArray(selected) || selected.length === 0) {
            return res.status(400).json({ error: 'selected scenes array is required' });
        }

        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const job = await db.getAsync(
            'SELECT id, project_id FROM queue_jobs WHERE id = ? AND project_id = ?',
            [jobId, req.params.id]
        );
        if (!job) {
            return res.status(404).json({ error: 'Job not found for project' });
        }

        const workDir = path.join(UPLOAD_ROOT, 'projects', req.params.id);
        await fs.mkdir(workDir, { recursive: true });
        const selectionPath = path.join(workDir, 'summary_selection.json');
        await fs.writeFile(
            selectionPath,
            JSON.stringify({ jobId, selected }, null, 2),
            'utf8'
        );

        await db.runAsync(
            `UPDATE queue_jobs
             SET status = 'pending', progress = 0.0, error_message = 'Scene selection received'
             WHERE id = ?`,
            [jobId]
        );

        const updatedJob = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [jobId]);

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('job:updated', {
                job: updatedJob,
                timestamp: new Date().toISOString(),
            });
        }

        res.json({ status: 'ok', job: updatedJob });
    } catch (error) {
        console.error('Submit summary selection error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get specific project by ID
router.get('/:id', authenticateToken, async (req, res) => {
    try {
        const project = await db.getAsync(
            `SELECT p.*, v.title as video_title, v.duration_sec, v.resolution, v.filename
       FROM projects p
       JOIN videos v ON p.video_id = v.id
       WHERE p.id = ? AND p.user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        res.json({ project });
    } catch (error) {
        console.error('Get project error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get project statistics (detailed chunk info)
router.get('/:id/stats', authenticateToken, async (req, res) => {
    try {
        // Verify project belongs to user
        const project = await db.getAsync(
            'SELECT * FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        // Get job statistics
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
            [req.params.id]
        );

        // Get queue position (if project is pending)
        let queuePosition = null;
        if (project.status === 'pending') {
            const result = await db.getAsync(
                `SELECT COUNT(*) + 1 as position
         FROM projects
         WHERE status = 'pending' AND created_at < ?`,
                [project.created_at]
            );
            queuePosition = result.position;
        }

        res.json({
            project,
            stats: {
                ...stats,
                queue_position: queuePosition,
                progress_percentage: project.progress * 100
            }
        });
    } catch (error) {
        console.error('Get project stats error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Update project
router.patch('/:id', authenticateToken, async (req, res) => {
    try {
        const { status, completedChunks, failedChunks, progress } = req.body;

        // Verify project belongs to user
        const project = await db.getAsync(
            'SELECT * FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const updates = [];
        const params = [];

        if (status !== undefined) {
            updates.push('status = ?');
            params.push(status);
        }

        if (completedChunks !== undefined) {
            updates.push('completed_chunks = ?');
            params.push(completedChunks);
        }

        if (failedChunks !== undefined) {
            updates.push('failed_chunks = ?');
            params.push(failedChunks);
        }

        if (progress !== undefined) {
            updates.push('progress = ?');
            params.push(progress);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No updates provided' });
        }

        updates.push('updated_at = CURRENT_TIMESTAMP');
        params.push(req.params.id);

        await db.runAsync(
            `UPDATE projects SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        const updatedProject = await db.getAsync(
            'SELECT * FROM projects WHERE id = ?',
            [req.params.id]
        );

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('project:updated', {
                project: updatedProject,
                timestamp: new Date().toISOString()
            });
        }

        res.json({ project: updatedProject });
    } catch (error) {
        console.error('Update project error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get project outputs
router.get('/:id/outputs', authenticateToken, async (req, res) => {
    try {
        const project = await db.getAsync(
            'SELECT id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        const outputs = await db.allAsync(
            'SELECT * FROM output_videos WHERE project_id = ? ORDER BY chunk_index ASC',
            [req.params.id]
        );

        res.json({ outputs });
    } catch (error) {
        console.error('Get project outputs error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Re-render project with new settings
router.post('/:id/re-render', authenticateToken, async (req, res) => {
    try {
        const { settings } = req.body;

        if (!settings) {
            return res.status(400).json({ error: 'Settings are required' });
        }

        // Verify project belongs to user
        const project = await db.getAsync(
            'SELECT * FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        // Increment version and update settings
        const newVersion = (project.version || 1) + 1;
        const settingsJson = JSON.stringify(settings);

        await db.runAsync(
            `UPDATE projects 
             SET settings_json = ?, version = ?, status = 'pending', 
                 completed_chunks = 0, failed_chunks = 0, progress = 0.0,
                 updated_at = CURRENT_TIMESTAMP
             WHERE id = ?`,
            [settingsJson, newVersion, req.params.id]
        );

        // Remove existing generated output files for this project
        const outputs = await db.allAsync(
            'SELECT file_path FROM output_videos WHERE project_id = ? AND file_path IS NOT NULL',
            [req.params.id]
        );
        for (const output of outputs) {
            try {
                await fs.unlink(output.file_path);
            } catch (err) {
                console.warn(`Could not delete output file ${output.file_path}:`, err.message);
            }
        }

        // Delete old jobs for this project (will cascade to outputs)
        await db.runAsync('DELETE FROM queue_jobs WHERE project_id = ?', [req.params.id]);

        // Recreate jobs for all chunks so project can be processed again
        for (let chunkIndex = 0; chunkIndex < project.total_chunks; chunkIndex++) {
            await db.runAsync(
                `INSERT INTO queue_jobs (id, project_id, video_id, chunk_index, status, progress)
                 VALUES (?, ?, ?, ?, 'pending', 0.0)`,
                [uuidv4(), req.params.id, project.video_id, chunkIndex]
            );
        }

        const updatedProject = await db.getAsync(
            'SELECT * FROM projects WHERE id = ?',
            [req.params.id]
        );

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('project:re-render', {
                project: updatedProject,
                timestamp: new Date().toISOString()
            });
        }

        res.json({
            project: updatedProject,
            message: 'Project queued for re-rendering'
        });
    } catch (error) {
        console.error('Re-render project error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Delete project (deletes jobs and outputs but PRESERVES original video)
router.delete('/:id', authenticateToken, async (req, res) => {
    try {
        // Verify project belongs to user
        const project = await db.getAsync(
            'SELECT id, video_id FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (!project) {
            return res.status(404).json({ error: 'Project not found' });
        }

        // Delete generated output files from filesystem (original video is NOT deleted)
        const outputs = await db.allAsync(
            'SELECT file_path FROM output_videos WHERE project_id = ? AND file_path IS NOT NULL',
            [req.params.id]
        );
        for (const output of outputs) {
            try {
                await fs.unlink(output.file_path);
            } catch (err) {
                console.warn(`Could not delete output file ${output.file_path}:`, err.message);
            }
        }

        // Explicitly delete related DB rows (don't rely on SQLite FK cascade)
        await db.runAsync(
            'DELETE FROM output_videos WHERE project_id = ?',
            [req.params.id]
        );
        await db.runAsync(
            'DELETE FROM queue_jobs WHERE project_id = ?',
            [req.params.id]
        );

        // Delete project row (original video remains untouched)
        const result = await db.runAsync(
            'DELETE FROM projects WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );

        if (result.changes === 0) {
            return res.status(404).json({ error: 'Project not found' });
        }

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('project:deleted', {
                projectId: req.params.id,
                videoId: project.video_id, // Original video is preserved
                timestamp: new Date().toISOString()
            });
        }

        res.json({
            message: 'Project deleted successfully',
            note: 'Original video preserved'
        });
    } catch (error) {
        console.error('Delete project error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
