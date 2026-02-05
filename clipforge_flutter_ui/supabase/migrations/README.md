# Supabase Migrations

## Running the Video Split Schema Migration

### Option 1: Supabase CLI (Recommended for local development)
```bash
# Make sure you're in the supabase directory
cd supabase

# Run the migration
supabase db push

# Or apply to remote
supabase db push --linked
```

### Option 2: Supabase Dashboard
1. Go to your Supabase project dashboard
2. Navigate to SQL Editor
3. Copy the contents of `migrations/20260201_create_video_split_schema.sql`
4. Paste and run

### Option 3: Direct SQL (for production)
```bash
psql "your-supabase-connection-string" < migrations/20260201_create_video_split_schema.sql
```

## What This Migration Creates

### Tables
- **projects**: Stores project metadata and settings
- **processing_jobs**: Tracks individual video chunk processing jobs
- **job_events**: Logs events for debugging (optional)

### Security
- Row Level Security (RLS) enabled on all tables
- Users can only access their own projects and jobs

### Automation
- Auto-updates `updated_at` timestamps
- Auto-calculates project progress
- Auto-sets project status based on job status

### Views
- **project_progress**: Summary view of project completion status

## Verifying the Migration

After running, verify with:
```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('projects', 'processing_jobs', 'job_events');

-- Check RLS is enabled
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('projects', 'processing_jobs', 'job_events');
```
