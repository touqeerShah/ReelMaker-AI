-- Users table
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  name TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Videos table (stores original video metadata)
CREATE TABLE IF NOT EXISTS videos (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT,
  filename TEXT,
  file_path TEXT,
  duration_sec REAL,
  resolution TEXT,
  size_bytes INTEGER,
  segment_duration INTEGER,
  overlay_duration REAL,
  logo_position TEXT DEFAULT 'bottom_right',
  watermark_enabled INTEGER DEFAULT 1,
  watermark_alpha REAL DEFAULT 0.55,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Projects table (tracks video processing with progress)
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  video_id TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT DEFAULT 'pending', -- pending, processing, completed, failed
  total_chunks INTEGER NOT NULL,
  completed_chunks INTEGER DEFAULT 0,
  failed_chunks INTEGER DEFAULT 0,
  progress REAL DEFAULT 0.0,
  settings_json TEXT,
  version INTEGER DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
);

-- Queue jobs table
CREATE TABLE IF NOT EXISTS queue_jobs (
  id TEXT PRIMARY KEY,
  project_id TEXT,
  video_id TEXT NOT NULL,
  chunk_index INTEGER,
  status TEXT DEFAULT 'pending',
  progress REAL DEFAULT 0.0,
  queue_position INTEGER,
  output_filename TEXT,
  output_path TEXT,
  error_message TEXT,
  started_at DATETIME,
  completed_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
  FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
);

-- Output videos table (tracks generated split videos)
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

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_videos_user_id ON videos(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_user_id ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_video_id ON projects(video_id);
CREATE INDEX IF NOT EXISTS idx_queue_jobs_project_id ON queue_jobs(project_id);
CREATE INDEX IF NOT EXISTS idx_queue_jobs_video_id ON queue_jobs(video_id);
CREATE INDEX IF NOT EXISTS idx_queue_jobs_status ON queue_jobs(status);
CREATE INDEX IF NOT EXISTS idx_output_videos_project_id ON output_videos(project_id);
CREATE INDEX IF NOT EXISTS idx_output_videos_job_id ON output_videos(job_id);

-- AI chunk analysis cache (for re-use/debugging)
CREATE TABLE IF NOT EXISTS ai_chunk_results (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  chunk_input_json TEXT NOT NULL,
  context_text TEXT,
  segments_json TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(project_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS idx_ai_chunk_results_project_id ON ai_chunk_results(project_id);
