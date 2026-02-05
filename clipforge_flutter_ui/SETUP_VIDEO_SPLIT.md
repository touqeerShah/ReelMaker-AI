# Video Split Backend - Setup & Testing Guide

## Prerequisites

1. **Supabase Setup**
   ```bash
   cd supabase
   supabase db push
   ```

2. **Watermark Image**
   - Place your watermark PNG in `assets/watermark.png`
   - Update `pubspec.yaml`:
     ```yaml
     flutter:
       assets:
         - assets/watermark.png
     ```

## Files Created

### Backend (Supabase)
- ✅ `supabase/migrations/20260201_create_video_split_schema.sql`
  - Projects, processing_jobs, job_events tables
  - RLS policies
  - Auto-triggers for progress tracking
  - Helper views

### Models
- ✅ `lib/models/processing_job.dart` - Job tracking with status & progress
- ✅ `lib/models/video_project.dart` - Project metadata with settings

### Services
- ✅ `lib/services/local_queue_db.dart` - SQLite for local job queue
- ✅ `lib/services/ffmpeg_processor.dart` - Video processing with FFmpeg
- ✅ `lib/services/video_queue_worker.dart` - Background worker
- ✅ `lib/services/queue_service.dart` - Real-time Supabase streaming

### UI Integration
- ✅ `lib/screens/create_shorts_wizard.dart` - Updated `_finish()` method

## How It Works

1. **User selects video** in wizard
2. **Wizard finish creates**:
   - Project in Supabase
   - Copies video to app storage
   - Calculates chunks
   - Generates jobs
   - Starts queue worker
3. **Queue worker**:
   - Polls for pending jobs
   - Processes with FFmpeg
   - Updates progress in local DB
   - Syncs to Supabase
4. **Queue screen**:
   - Streams projects from Supabase
   - Shows real-time progress
   - Allows retry/delete

## Testing Checklist

### 1. Basic Flow
- [ ] Select a 3-minute video
- [ ] Set 60s chunks
- [ ] Complete wizard
- [ ] Verify project created in Supabase
- [ ] Verify jobs created (should be 3)
- [ ] Check video copied to app storage
- [ ] Verify queue worker started

### 2. Video Processing
- [ ] Check first job starts processing
- [ ] Verify progress updates in Supabase
- [ ] Verify output file created
- [ ] Check watermark is visible (bottom-right)
- [ ] Check channel name visible (random position)
- [ ] Verify 9:16 aspect ratio (no cropping, padding added)

### 3. Error Handling
- [ ] Test with video without audio
- [ ] Test with corrupted video
- [ ] Test with very short video (< segment duration)
- [ ] Verify error messages appear
- [ ] Check job marked as failed

### 4. Queue Management
- [ ] Verify sequential processing (one at a time)
- [ ] Test pause/resume (if implemented)
- [ ] Test cancel job
- [ ] Test delete project
- [ ] Verify cleanup of local files

## Known Limitations

1. **Web support**: Currently disabled (file system operations)
2. **Watermark**: Requires manual asset placement
3. **Background processing**: May stop when app is terminated (needs foreground service on Android)
4. **Progress accuracy**: Depends on FFmpeg statistics callback

## FFmpeg Command Reference

The processor builds commands like:
```bash
ffmpeg -y -ss 0.000 -t 60.000 -i "input.mp4" -i "watermark.png"   -filter_complex "[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v0];[1:v]scale=180:-1,format=rgba,colorchannelmixer=aa=0.55[wm];[v0][wm]overlay=W-w-40:H-h-40[v1];[v1]drawtext=text='My Channel':x=250:y=800:fontsize=36:fontcolor=white:borderw=3:bordercolor=black@0.6[v]"   -map "[v]" -map 0:a:0?   -c:v libx264 -preset veryfast -crf 20   -c:a aac -b:a 192k   -movflags +faststart   "output.mp4"
```

## Troubleshooting

### Jobs stuck in pending
- Check queue worker is running: `VideoQueueWorker().isRunning`
- Check local DB: `await LocalQueueDb().getNextPendingJob()`
- Restart worker: `await VideoQueueWorker().start()`

### FFmpeg errors
- Check watermark path exists
- Verify input video is valid
- Check FFmpeg logs in console

### Supabase sync failing
- Check user is authenticated
- Verify RLS policies are applied
- Check network connection

## Next Steps

1. **Add foreground service** (Android) for background processing
2. **Implement pause/resume** for queue worker
3. **Add video preview** in Queue screen
4. **Optimize FFmpeg settings** for different devices
5. **Add batch operations** (process multiple projects)
6. **Implement retry logic** for failed jobs
