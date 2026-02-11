require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const { startQueueWorker } = require('./worker/queue_worker');

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const VOICES_DIR = process.env.VOICES_DIR || './voices_out';

// Import routes
const authRoutes = require('./routes/auth');
const videoRoutes = require('./routes/videos');
const queueRoutes = require('./routes/queue');
const projectRoutes = require('./routes/projects');
const outputRoutes = require('./routes/outputs');
const aiRoutes = require('./routes/ai');
const uploadRoutes = require('./routes/uploads');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors()); // Enable CORS for all origins
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(path.resolve(UPLOAD_DIR)));
app.use('/voices', express.static(path.resolve(VOICES_DIR)));

// Request logging
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
    next();
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/videos', videoRoutes);
app.use('/api/queue', queueRoutes);
app.use('/api/projects', projectRoutes);
app.use('/api/outputs', outputRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/uploads', uploadRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        name: 'ReelMaker Backend API',
        version: '1.0.0',
        endpoints: {
            auth: '/api/auth',
            videos: '/api/videos',
            queue: '/api/queue',
            projects: '/api/projects',
            outputs: '/api/outputs',
            ai: '/api/ai',
            health: '/health'
        }
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(err.status || 500).json({
        error: err.message || 'Internal server error'
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
    console.log('=================================');
    console.log('ReelMaker Backend Server Started');
    console.log('=================================');
    console.log(`Port: ${PORT}`);
    console.log(`Time: ${new Date().toISOString()}`);
    console.log('');
    console.log('Find your local IP address:');
    console.log('  macOS/Linux: ifconfig | grep "inet "');
    console.log('  Windows: ipconfig');
    console.log('');
    console.log('Access the API from your phone at:');
    console.log(`  http://<YOUR_LOCAL_IP>:${PORT}`);
    console.log('=================================');
});

// WebSocket Setup with Socket.IO
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');

const io = new Server(server, {
    cors: {
        origin: '*',
        methods: ['GET', 'POST']
    }
});

// Authenticate WebSocket connections using JWT
io.use((socket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) {
        return next(new Error('Authentication token required'));
    }

    try {
        const user = jwt.verify(token, process.env.JWT_SECRET);
        socket.userId = user.id;
        socket.userEmail = user.email;
        next();
    } catch (err) {
        next(new Error('Invalid authentication token'));
    }
});

// WebSocket connection handler
io.on('connection', (socket) => {
    console.log(`🔌 WebSocket: User ${socket.userEmail} connected`);

    // Join user-specific room for targeted broadcasts
    socket.join(`user:${socket.userId}`);

    // Handle job progress updates from client
    socket.on('job:progress', async (data) => {
        const { jobId, progress, status } = data;
        console.log(`📊 Progress update: Job ${jobId} - ${progress}%`);

        // Broadcast to all user's connected devices
        io.to(`user:${socket.userId}`).emit('job:updated', {
            jobId,
            progress,
            status,
            timestamp: new Date().toISOString()
        });
    });

    // Handle job completion
    socket.on('job:completed', async (data) => {
        const { jobId, outputFilename } = data;
        console.log(`✅ Job completed: ${jobId}`);

        io.to(`user:${socket.userId}`).emit('job:completed', {
            jobId,
            outputFilename,
            timestamp: new Date().toISOString()
        });
    });

    // Handle job failure
    socket.on('job:failed', async (data) => {
        const { jobId, error } = data;
        console.log(`❌ Job failed: ${jobId} - ${error}`);

        io.to(`user:${socket.userId}`).emit('job:failed', {
            jobId,
            error,
            timestamp: new Date().toISOString()
        });
    });

    socket.on('disconnect', () => {
        console.log(`🔌 WebSocket: User ${socket.userEmail} disconnected`);
    });
});

// Make io available to routes
app.set('io', io);
startQueueWorker(io);

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, closing server...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('SIGINT received, closing server...');
    process.exit(0);
});
