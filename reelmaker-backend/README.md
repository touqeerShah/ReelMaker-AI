# ReelMaker Backend Server

Local backend API server for ReelMaker AI video processing application.

## Features

- **Authentication**: JWT-based user registration and login
- **Video Management**: Upload, list, and manage video files
- **Queue Management**: Create and track video processing jobs
- **Local Network Access**: Accessible from phone and Mac on same WiFi

## Setup

### 1. Install Dependencies

```bash
cd reelmaker-backend
npm install
```

### 2. Configure Environment

Edit `.env` file if needed:
```env
PORT=3000
JWT_SECRET=your-super-secret-jwt-key-change-this
DB_PATH=./reelmaker.db
UPLOAD_DIR=./uploads
```

### 3. Create Uploads Directory

```bash
mkdir -p uploads
```

### 4. Start Server

```bash
npm start
```

For development with auto-restart:
```bash
npm run dev
```

## Find Your Local IP

**macOS/Linux:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

**Windows:**
```bash
ipconfig
```

Look for IPv4 address like `192.168.1.x` or `10.0.0.x`

## API Endpoints

### Authentication

**Register**
```http
POST /api/auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "password123",
  "name": "John Doe"
}
```

**Login**
```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "password123"
}
```

**Get Current User**
```http
GET /api/auth/me
Authorization: Bearer <token>
```

### Videos

**Upload Video**
```http
POST /api/videos/upload
Authorization: Bearer <token>
Content-Type: multipart/form-data

video: <file>
title: "My Video"
durationSec: 120.5
resolution: "1920x1080"
```

**List Videos**
```http
GET /api/videos
Authorization: Bearer <token>
```

**Get Video Details**
```http
GET /api/videos/:id
Authorization: Bearer <token>
```

**Delete Video**
```http
DELETE /api/videos/:id
Authorization: Bearer <token>
```

### Queue

**Create Job**
```http
POST /api/queue/jobs
Authorization: Bearer <token>
Content-Type: application/json

{
  "videoId": "uuid",
  "chunkIndex": 0,
  "outputFilename": "chunk_0.mp4"
}
```

**List Jobs**
```http
GET /api/queue/jobs?videoId=uuid&status=pending
Authorization: Bearer <token>
```

**Update Job**
```http
PATCH /api/queue/jobs/:id
Authorization: Bearer <token>
Content-Type: application/json

{
  "status": "running",
  "progress": 0.5
}
```

## Testing

### Test with curl

```bash
# Health check
curl http://localhost:3000/health

# Register
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123","name":"Test User"}'

# Login
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

## Project Structure

```
reelmaker-backend/
├── server.js              # Main Express application
├── package.json          # Dependencies
├── .env                  # Environment configuration
├── database/
│   ├── db.js            # SQLite connection
│   └── schema.sql       # Database schema
├── routes/
│   ├── auth.js          # Authentication routes
│   ├── videos.js        # Video management routes
│   └── queue.js         # Queue management routes
├── middleware/
│   ├── auth.js          # JWT authentication
│   └── upload.js        # File upload handling
├── uploads/             # Video file storage
└── reelmaker.db        # SQLite database
```

## Security Notes

- Change `JWT_SECRET` in production
- Use HTTPS for production deployments
- Implement rate limiting for auth endpoints
- Add file size and type validation
- Consider adding request logging

## Troubleshooting

**Cannot access from phone:**
1. Ensure both devices are on same WiFi network
2. Check firewall settings on Mac
3. Verify server is listening on `0.0.0.0`, not `localhost`
4. Use correct local IP address (not 127.0.0.1)

**Port already in use:**
```bash
# Find process using port 3000
lsof -i :3000
# Kill the process
kill -9 <PID>
```
