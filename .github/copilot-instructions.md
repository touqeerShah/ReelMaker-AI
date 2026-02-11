# Copilot / AI Agent Instructions for ReelMaker-AI ✅

## Quick high-level summary
- Repo purpose: offline-first video processing—split, subtitle, translate, summarize, and render short videos using FFmpeg + Whisper + TTS. See `README.md` and `README-dev.md` for overall design and motivation.
- Two primary apps: a local Node backend (`reelmaker-backend/`) and a Flutter UI (`clipforge_flutter_ui/`). A lightweight web UI exists in `index.html` / `app.js` for demos.

## Architecture & important boundaries 🔧
- Backend (local dev): `reelmaker-backend/` (Express + SQLite). Key files: `server.js`, `routes/*.js`, `database/schema.sql`, `middleware/*.js`.
- Mobile UI: `clipforge_flutter_ui/` (Flutter). Key services: `lib/services/local_backend_api.dart` (REST helpers) and `lib/services/queue_sync_service.dart` (WebSocket client).
- Offline ML: `whisper.cpp/` submodule is used for on-device transcription. FFmpeg commands + templates are documented in `README-dev.md` and `backend-steps.md`.

## Developer workflows (concrete steps) ▶️
- Start backend (default port):
  cd reelmaker-backend && npm install && npm start
- Development mode: `npm run dev` (uses `nodemon`).
- Run backend verification script: `reelmaker-backend/test-endpoints.sh` (expects `BASE_URL` default `http://localhost:4000`—set `PORT` or edit the script as needed).
- Flutter UI: open `clipforge_flutter_ui/` and run `flutter run` (ensure Android/iOS toolchains and environment variables per `installation-guide-run-app-on-phone.md`).
- FFmpeg/transcription quick commands are in `README-dev.md` (extract 16k mono WAV for whisper, cut/concat templates, muxing commands). Use those exact command templates when implementing or testing native processing.

## Key conventions & patterns to keep in mind 🧭
- Transcribe once per source video (whisper.cpp → `transcript.json`) and re-use that output for per-clip SRT generation and summarization. (See `README-dev.md`: "Whisper transcript once" / "Never re-run whisper per clip").
- Per-clip subtitles are derived by filtering global transcript segments and rebasing timestamps (fast and deterministic). Don’t re-run ASR per clip.
- Job lifecycle and schema: `queue_jobs` with statuses `pending | running | completed | failed`; projects track progress in `projects` (see `database/schema.sql`).
- WebSocket events: backend emits `job:created`, `job:updated`, `job:completed`, `job:failed` to user rooms named `user:<userId>` (see `server.js` io.emit usage). Flutter client uses `QueueSyncService` to listen/emit these.
- Authentication: backend uses JWT (`middleware/auth.js`). Default dev secret = `default-secret-change-me`—**change before public deployments**.

## Useful code references (examples) 📌
- Create job (REST): `POST /api/queue/jobs` → `reelmaker-backend/routes/queue.js` (position calculation, emits `job:created`).
- Uploads and size limits: `reelmaker-backend/middleware/upload.js` enforces video MIME list and 500MB max.
- Local API service in Flutter: `clipforge_flutter_ui/lib/services/local_backend_api.dart` (shows exact header and JSON shape for all endpoints).
- FFmpeg/TTS timing tips: `README-dev.md` contains the recommended approach for TTS alignment (compress/pad short TTS segments; concat and mux).

## Tests & quick checks ✅
- Health check: `GET /health`.
- Use the `test-endpoints.sh` script to verify routes and DB schema (ensure `PORT` matches the script's `BASE_URL`).
- Example debug commands (from `reelmaker-backend/test-endpoints.sh`):
  - Register: `curl -X POST $BASE_URL/api/auth/register -H 'Content-Type: application/json' -d '{"email":"test@test.com","password":"password"}'`
  - Login to get token, then add `Authorization: Bearer <token>` to protected requests.

## When to ask for human help / non-actionable items ❗
- If you need new model weights or large binaries (e.g., Whisper model files), confirm storage & license decisions before adding or downloading into repo.
- For cross-device/background scheduling, confirm whether automation will run on-device or be moved to a small backend (the README-dev recommends a backend for reliable cross-platform scheduling).

## Implementation guardrails for AI agents 🛡️
- Keep the "transcribe once" invariant—do not add per-clip Whisper runs.
- Respect DB schema and use `db.runAsync`, `db.getAsync`, `db.allAsync` helpers (see `reelmaker-backend/database/db.js`).
- Emit WebSocket events exactly as other code expects (use the `user:<id>` room pattern). Tests and UI rely on these event names.
- Use existing FFmpeg command templates from `README-dev.md` and `backend-steps.md` rather than inventing new variants unless necessary.
- Log errors consistently and return generic 500 messages (mirrors current style in routes).


## Recent backend behavior conventions ✅
- Project title defaults to the video's filename when the client does not provide a title (backend will strip extension).
- Output filenames are deterministic: when the renderer does not supply a filename, the backend will generate one using `<originalBase>_NNN.ext` (3-digit zero-padded chunk index).
- Re-rendering a project (`POST /api/projects/:id/re-render`) increments the project version, resets progress, and removes old jobs/outputs so clients can queue new jobs with updated settings.

---
Please review these instructions and tell me any missing pieces or unclear sections to iterate. Would you like me to add a short checklist for onboarding new contributors (install, run, quick test)? ✨
