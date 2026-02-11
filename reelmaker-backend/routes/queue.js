const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../database/db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

async function recalculateProjectProgress(projectId) {
    const counts = await db.getAsync(
        `SELECT
           COUNT(*) as total_jobs,
           SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending_jobs,
           SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running_jobs,
           SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_jobs,
           SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_jobs
         FROM queue_jobs
         WHERE project_id = ?`,
        [projectId]
    );

    const total = counts?.total_jobs || 0;
    const pending = counts?.pending_jobs || 0;
    const running = counts?.running_jobs || 0;
    const completed = counts?.completed_jobs || 0;
    const failed = counts?.failed_jobs || 0;
    const progress = total > 0 ? completed / total : 0.0;

    let projectStatus = 'pending';
    if (total > 0 && completed === total) {
        projectStatus = 'completed';
    } else if (total > 0 && failed > 0 && (completed + failed) === total) {
        projectStatus = 'failed';
    } else if (running > 0 || completed > 0 || failed > 0) {
        projectStatus = 'processing';
    } else if (pending === total) {
        projectStatus = 'pending';
    }

    await db.runAsync(
        `UPDATE projects
         SET status = ?, completed_chunks = ?, failed_chunks = ?, progress = ?, updated_at = CURRENT_TIMESTAMP
         WHERE id = ?`,
        [projectStatus, completed, failed, progress, projectId]
    );

    return await db.getAsync('SELECT * FROM projects WHERE id = ?', [projectId]);
}

// Get overall queue statistics
router.get('/stats', authenticateToken, async (req, res) => {
    try {
        // Get overall statistics for all user's jobs
        const stats = await db.getAsync(
            `SELECT 
        COUNT(*) as total_jobs,
        SUM(CASE WHEN qj.status = 'pending' THEN 1 ELSE 0 END) as pending_jobs,
        SUM(CASE WHEN qj.status = 'running' THEN 1 ELSE 0 END) as running_jobs,
        SUM(CASE WHEN qj.status = 'completed' THEN 1 ELSE 0 END) as completed_jobs,
        SUM(CASE WHEN qj.status = 'failed' THEN 1 ELSE 0 END) as failed_jobs
      FROM queue_jobs qj
      JOIN videos v ON qj.video_id = v.id
      WHERE v.user_id = ?`,
            [req.user.id]
        );

        res.json({ stats });
    } catch (error) {
        console.error('Get queue stats error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get queue statistics for a specific video
router.get('/stats/:videoId', authenticateToken, async (req, res) => {
    try {
        // Verify video belongs to user
        const video = await db.getAsync(
            'SELECT id FROM videos WHERE id = ? AND user_id = ?',
            [req.params.videoId, req.user.id]
        );

        if (!video) {
            return res.status(404).json({ error: 'Video not found' });
        }

        const stats = await db.getAsync(
            `SELECT 
        COUNT(*) as total_jobs,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending_jobs,
        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running_jobs,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_jobs,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_jobs,
        AVG(progress) as avg_progress
      FROM queue_jobs
      WHERE video_id = ?`,
            [req.params.videoId]
        );

        res.json({ stats });
    } catch (error) {
        console.error('Get video queue stats error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Create a new queue job
router.post('/jobs', authenticateToken, async (req, res) => {
    try {
        const { videoId, projectId, chunkIndex, outputFilename } = req.body;

        if (!videoId) {
            return res.status(400).json({ error: 'videoId is required' });
        }

        // Verify video belongs to user
        const video = await db.getAsync(
            'SELECT id FROM videos WHERE id = ? AND user_id = ?',
            [videoId, req.user.id]
        );

        if (!video) {
            return res.status(404).json({ error: 'Video not found' });
        }

        // Calculate queue position (number of pending jobs + 1)
        const queuePositionResult = await db.getAsync(
            `SELECT COUNT(*) + 1 as position FROM queue_jobs WHERE status = 'pending'`
        );
        const queuePosition = queuePositionResult.position;

        const jobId = uuidv4();

        await db.runAsync(
            `INSERT INTO queue_jobs (id, project_id, video_id, chunk_index, queue_position, output_filename)
       VALUES (?, ?, ?, ?, ?, ?)`,
            [jobId, projectId || null, videoId, chunkIndex || null, queuePosition, outputFilename || null]
        );

        const job = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [jobId]);

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('job:created', {
                job,
                timestamp: new Date().toISOString()
            });
        }

        res.status(201).json({ job });
    } catch (error) {
        console.error('Create job error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Create multiple queue jobs in batch
router.post('/jobs/batch', authenticateToken, async (req, res) => {
    try {
        const { jobs } = req.body;

        if (!jobs || !Array.isArray(jobs) || jobs.length === 0) {
            return res.status(400).json({ error: 'jobs array is required and must not be empty' });
        }

        // Verify all videos belong to user
        const videoIds = [...new Set(jobs.map(j => j.videoId))];
        for (const videoId of videoIds) {
            const video = await db.getAsync(
                'SELECT id FROM videos WHERE id = ? AND user_id = ?',
                [videoId, req.user.id]
            );

            if (!video) {
                return res.status(404).json({ error: `Video ${videoId} not found` });
            }
        }

        const createdJobs = [];

        // Create all jobs in a transaction
        await new Promise((resolve, reject) => {
            db.serialize(async () => {
                try {
                    for (const jobData of jobs) {
                        const { videoId, projectId, chunkIndex, outputFilename } = jobData;
                        const jobId = jobData.id || uuidv4();

                        await db.runAsync(
                            `INSERT INTO queue_jobs (id, project_id, video_id, chunk_index, status, progress, output_filename)
                             VALUES (?, ?, ?, ?, 'pending', 0.0, ?)`,
                            [jobId, projectId || null, videoId, chunkIndex || null, outputFilename || null]
                        );

                        const job = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [jobId]);
                        createdJobs.push(job);
                    }

                    resolve();
                } catch (err) {
                    reject(err);
                }
            });
        });

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${req.user.id}`).emit('jobs:created', {
                jobs: createdJobs,
                timestamp: new Date().toISOString()
            });
        }

        res.status(201).json({ jobs: createdJobs });
    } catch (error) {
        console.error('Create batch jobs error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get jobs (filterable by video_id and status)
router.get('/jobs', authenticateToken, async (req, res) => {
    try {
        const { videoId, projectId, status } = req.query;

        let query = `
      SELECT qj.*, p.title as project_title
      FROM queue_jobs qj
      JOIN videos v ON qj.video_id = v.id
      LEFT JOIN projects p ON p.id = qj.project_id
      WHERE v.user_id = ?
    `;
        const params = [req.user.id];

        if (videoId) {
            query += ' AND qj.video_id = ?';
            params.push(videoId);
        }

        if (projectId) {
            query += ' AND qj.project_id = ?';
            params.push(projectId);
        }

        if (status) {
            query += ' AND qj.status = ?';
            params.push(status);
        }

        query += ' ORDER BY qj.chunk_index ASC, qj.created_at DESC';

        const jobs = await db.allAsync(query, params);

        res.json({ jobs });
    } catch (error) {
        console.error('Get jobs error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Get specific job
router.get('/jobs/:id', authenticateToken, async (req, res) => {
    try {
        const job = await db.getAsync(
            `SELECT qj.* 
       FROM queue_jobs qj
       JOIN videos v ON qj.video_id = v.id
       WHERE qj.id = ? AND v.user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (!job) {
            return res.status(404).json({ error: 'Job not found' });
        }

        res.json({ job });
    } catch (error) {
        console.error('Get job error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Update job status/progress
router.patch('/jobs/:id', authenticateToken, async (req, res) => {
    try {
        const { status, progress, errorMessage, outputFilename, outputPath } = req.body;
        console.log(
            `[queue.patch] job=${req.params.id} status=${status ?? '-'} progress=${progress ?? '-'} step=${errorMessage ?? '-'}`
        );

        // Verify job belongs to user
        const job = await db.getAsync(
            `SELECT qj.id 
       FROM queue_jobs qj
       JOIN videos v ON qj.video_id = v.id
       WHERE qj.id = ? AND v.user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (!job) {
            return res.status(404).json({ error: 'Job not found' });
        }

        const updates = [];
        const params = [];

        if (status !== undefined) {
            updates.push('status = ?');
            params.push(status);

            if (status === 'running') {
                updates.push('started_at = CURRENT_TIMESTAMP');
            } else if (status === 'completed' || status === 'failed') {
                updates.push('completed_at = CURRENT_TIMESTAMP');
            }
        }

        if (progress !== undefined) {
            updates.push('progress = ?');
            params.push(progress);
        }

        if (errorMessage !== undefined) {
            updates.push('error_message = ?');
            params.push(errorMessage);
        }

        if (outputFilename !== undefined) {
            updates.push('output_filename = ?');
            params.push(outputFilename);
        }

        if (outputPath !== undefined) {
            updates.push('output_path = ?');
            params.push(outputPath);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No updates provided' });
        }

        params.push(req.params.id);

        await db.runAsync(
            `UPDATE queue_jobs SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        const updatedJob = await db.getAsync('SELECT * FROM queue_jobs WHERE id = ?', [req.params.id]);
        console.log(
            `[queue.patch.done] job=${updatedJob?.id} status=${updatedJob?.status} progress=${updatedJob?.progress} step=${updatedJob?.error_message ?? '-'}`
        );

        let updatedProject = null;
        if (updatedJob?.project_id) {
            updatedProject = await recalculateProjectProgress(updatedJob.project_id);
        }

        // Emit WebSocket event
        const io = req.app.get('io');
        if (io) {
            // Get user_id from the video
            const video = await db.getAsync(
                'SELECT user_id FROM videos WHERE id = ?',
                [updatedJob.video_id]
            );

            if (video) {
                io.to(`user:${video.user_id}`).emit('job:updated', {
                    job: updatedJob,
                    timestamp: new Date().toISOString()
                });

                if (updatedJob.status === 'completed') {
                    io.to(`user:${video.user_id}`).emit('job:completed', {
                        job: updatedJob,
                        timestamp: new Date().toISOString()
                    });
                } else if (updatedJob.status === 'failed') {
                    io.to(`user:${video.user_id}`).emit('job:failed', {
                        job: updatedJob,
                        timestamp: new Date().toISOString()
                    });
                }

                if (updatedProject) {
                    io.to(`user:${video.user_id}`).emit('project:updated', {
                        project: updatedProject,
                        timestamp: new Date().toISOString()
                    });
                }
            }
        }

        res.json({ job: updatedJob });
    } catch (error) {
        console.error('Update job error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Delete job
router.delete('/jobs/:id', authenticateToken, async (req, res) => {
    try {
        const existing = await db.getAsync(
            `SELECT qj.id, qj.project_id
             FROM queue_jobs qj
             JOIN videos v ON qj.video_id = v.id
             WHERE qj.id = ? AND v.user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (!existing) {
            return res.status(404).json({ error: 'Job not found' });
        }

        const result = await db.runAsync(
            `DELETE FROM queue_jobs 
       WHERE id = ? AND video_id IN (
         SELECT id FROM videos WHERE user_id = ?
       )`,
            [req.params.id, req.user.id]
        );

        if (result.changes === 0) {
            return res.status(404).json({ error: 'Job not found' });
        }

        if (existing.project_id) {
            await recalculateProjectProgress(existing.project_id);
        }

        res.json({ message: 'Job deleted successfully' });
    } catch (error) {
        console.error('Delete job error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
