// server.js
require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');

const app = express();

// Middlewares
app.use(helmet());
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(morgan('combined'));

// CORS: restrict in production
const corsOptions = {
  origin: process.env.NODE_ENV === 'production' ? (process.env.CORS_ORIGIN || []) : true,
  methods: ['GET','POST','PUT','DELETE','OPTIONS']
};
app.use(cors(corsOptions));

// Rate limiter
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 300, // adjust as needed
  standardHeaders: true,
  legacyHeaders: false
});
app.use(limiter);

// Routes
const reportRoutes = require('./routes/reports');
app.use('/api', reportRoutes);

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    message: 'DAML Server is running',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

app.get('/', (req, res) => {
  res.json({
    message: 'DAML Server API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      sync: '/api/sync_reports',
      reports: '/api/reports'
    }
  });
});

// MongoDB connection
const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;
if (!mongoUri) {
  console.error("❌ MongoDB connection URI is required (set MONGODB_URI)");
  process.exit(1);
}

mongoose.connect(mongoUri, {
  // modern mongoose (v6+) ignores useNewUrlParser/useUnifiedTopology but leaving options is fine
  autoIndex: true,
})
.then(() => {
  console.log("✅ MongoDB connected successfully");
})
.catch(err => {
  console.error("❌ MongoDB connection error:", err.message);
  process.exit(1);
});

// Error handling middleware (should be after routes)
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({
    success: false,
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'production' ? 'Something went wrong' : err.message
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
    path: req.path
  });
});

// Start server
const PORT = process.env.PORT || 5000;
const server = app.listen(PORT, () => {
  console.log(`🚀 DAML Server running on port ${PORT}`);
  console.log(`🌐 Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Graceful shutdown
const shutdown = async (signal) => {
  console.log(`\nReceived ${signal}. Closing server...`);
  server.close(async () => {
    try {
      await mongoose.disconnect();
      console.log('MongoDB disconnected. Exiting.');
      process.exit(0);
    } catch (err) {
      console.error('Error during shutdown', err);
      process.exit(1);
    }
  });
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
