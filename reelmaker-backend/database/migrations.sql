-- Migration script for ReelMaker-AI database enhancements
-- Run this to upgrade existing databases

-- Add new columns to projects table
ALTER TABLE projects ADD COLUMN settings_json TEXT;
ALTER TABLE projects ADD COLUMN version INTEGER DEFAULT 1;

-- Add output_path to queue_jobs
ALTER TABLE queue_jobs ADD COLUMN output_path TEXT;

-- Create output_videos table for tracking generated split videos
CREATE TABLE IF NOT EXISTS output_videos (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  job_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  filename TEXT NOT NULL,
  file_path TEXT,
  duration_sec REAL,
  size_bytes INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
  FOREIGN KEY (job_id) REFERENCES queue_jobs(id) ON DELETE CASCADE
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_output_videos_project_id ON output_videos(project_id);
CREATE INDEX IF NOT EXISTS idx_output_videos_job_id ON output_videos(job_id);

-- Add segment_duration and other video settings columns to videos table
ALTER TABLE videos ADD COLUMN segment_duration INTEGER;
ALTER TABLE videos ADD COLUMN overlay_duration REAL;
ALTER TABLE videos ADD COLUMN logo_position TEXT DEFAULT 'bottom_right';
ALTER TABLE videos ADD COLUMN watermark_enabled INTEGER DEFAULT 1;
ALTER TABLE videos ADD COLUMN watermark_alpha REAL DEFAULT 0.55;
