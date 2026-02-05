ww-- Video Split Backend Schema
-- Creates tables for project management and job queue

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PROJECTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  source_filename TEXT NOT NULL,
  source_duration_sec REAL,
  source_resolution TEXT, -- e.g. "1920x1080"
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
  total_chunks INT,
  completed_chunks INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for projects
CREATE INDEX IF NOT EXISTS idx_projects_user_id ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_created_at ON projects(created_at DESC);

-- ============================================================
-- PROCESSING JOBS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS processing_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
  chunk_index INT NOT NULL,
  start_sec REAL NOT NULL,
  duration_sec REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, running, completed, failed
  progress REAL DEFAULT 0, -- 0.0 to 1.0
  output_filename TEXT,
  error_message TEXT,
  processing_started_at TIMESTAMPTZ,
  processing_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for processing_jobs
CREATE INDEX IF NOT EXISTS idx_jobs_project_id ON processing_jobs(project_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON processing_jobs(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_project_chunk ON processing_jobs(project_id, chunk_index);

-- ============================================================
-- JOB EVENTS TABLE (Optional - for debugging)
-- ============================================================
CREATE TABLE IF NOT EXISTS job_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES processing_jobs(id) ON DELETE CASCADE NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  message TEXT NOT NULL,
  log_level TEXT DEFAULT 'info', -- info, warning, error
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for job_events
CREATE INDEX IF NOT EXISTS idx_job_events_job_id ON job_events(job_id);
CREATE INDEX IF NOT EXISTS idx_job_events_timestamp ON job_events(timestamp DESC);

-- ============================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE processing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_events ENABLE ROW LEVEL SECURITY;

-- Projects: Users can only access their own projects
CREATE POLICY "Users can view their own projects"
  ON projects FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own projects"
  ON projects FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own projects"
  ON projects FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own projects"
  ON projects FOR DELETE
  USING (auth.uid() = user_id);

-- Processing Jobs: Users can access jobs from their projects
CREATE POLICY "Users can view jobs from their projects"
  ON processing_jobs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = processing_jobs.project_id
      AND projects.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert jobs for their projects"
  ON processing_jobs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = processing_jobs.project_id
      AND projects.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update jobs from their projects"
  ON processing_jobs FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = processing_jobs.project_id
      AND projects.user_id = auth.uid()
    )
  );

-- Job Events: Users can access events from their jobs
CREATE POLICY "Users can view events from their jobs"
  ON job_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM processing_jobs j
      JOIN projects p ON p.id = j.project_id
      WHERE j.id = job_events.job_id
      AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert events for their jobs"
  ON job_events FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM processing_jobs j
      JOIN projects p ON p.id = j.project_id
      WHERE j.id = job_events.job_id
      AND p.user_id = auth.uid()
    )
  );

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to projects
CREATE TRIGGER trigger_projects_updated_at
BEFORE UPDATE ON projects
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Apply updated_at trigger to processing_jobs
CREATE TRIGGER trigger_jobs_updated_at
BEFORE UPDATE ON processing_jobs
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Function to update project progress when jobs complete
CREATE OR REPLACE FUNCTION update_project_progress()
RETURNS TRIGGER AS $$
BEGIN
  -- Update completed chunks count
  UPDATE projects
  SET 
    completed_chunks = (
      SELECT COUNT(*)
      FROM processing_jobs
      WHERE project_id = NEW.project_id
      AND status = 'completed'
    ),
    updated_at = NOW()
  WHERE id = NEW.project_id;
  
  -- Check if all jobs are completed
  UPDATE projects p
  SET status = 'completed'
  WHERE p.id = NEW.project_id
  AND p.total_chunks = (
    SELECT COUNT(*)
    FROM processing_jobs j
    WHERE j.project_id = p.id
    AND j.status = 'completed'
  )
  AND p.status != 'completed';
  
  -- Check if any job failed
  UPDATE projects p
  SET status = 'failed'
  WHERE p.id = NEW.project_id
  AND EXISTS (
    SELECT 1
    FROM processing_jobs j
    WHERE j.project_id = p.id
    AND j.status = 'failed'
  )
  AND p.status != 'failed';
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update project progress when job status changes
CREATE TRIGGER trigger_update_project_progress
AFTER UPDATE OF status ON processing_jobs
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_project_progress();

-- Function to set project status to processing when first job starts
CREATE OR REPLACE FUNCTION set_project_processing()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'running' AND OLD.status = 'pending' THEN
    UPDATE projects
    SET status = 'processing'
    WHERE id = NEW.project_id
    AND status = 'pending';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to set project as processing
CREATE TRIGGER trigger_set_project_processing
AFTER UPDATE OF status ON processing_jobs
FOR EACH ROW
WHEN (NEW.status = 'running' AND OLD.status = 'pending')
EXECUTE FUNCTION set_project_processing();

-- ============================================================
-- HELPER VIEWS (Optional - for easier querying)
-- ============================================================

-- View showing project progress summary
CREATE OR REPLACE VIEW project_progress AS
SELECT 
  p.id,
  p.user_id,
  p.title,
  p.status,
  p.total_chunks,
  p.completed_chunks,
  CASE 
    WHEN p.total_chunks > 0 THEN (p.completed_chunks::FLOAT / p.total_chunks::FLOAT)
    ELSE 0
  END AS progress_percentage,
  COUNT(CASE WHEN j.status = 'running' THEN 1 END) AS running_jobs,
  COUNT(CASE WHEN j.status = 'failed' THEN 1 END) AS failed_jobs,
  p.created_at,
  p.updated_at
FROM projects p
LEFT JOIN processing_jobs j ON j.project_id = p.id
GROUP BY p.id;

-- Grant select on view to authenticated users
GRANT SELECT ON project_progress TO authenticated;
