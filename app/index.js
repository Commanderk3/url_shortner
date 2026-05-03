const express = require('express');
const redis = require('redis');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 8000;

// Middleware
app.use(express.json());

// Redis connection
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.on('error', (err) => console.error('Redis Error:', err));
redisClient.on('connect', () => console.log('Connected to Redis'));

// Helper function to generate short code
function generateShortCode(length = 6) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Connect to Redis and start server
async function startServer() {
  await redisClient.connect();
  
  // Routes
  app.get('/health', (req, res) => {
    res.json({ 
      status: 'healthy', 
      redis: redisClient.isReady ? 'connected' : 'disconnected',
      timestamp: new Date().toISOString()
    });
  });

  app.get('/', (req, res) => {
    res.json({
      message: 'URL Shortener API with Redis',
      endpoints: {
        shorten: 'POST /shorten - {"url": "https://example.com"}',
        redirect: 'GET /{short_code}',
        stats: 'GET /stats/{short_code}',
        health: 'GET /health'
      }
    });
  });

  // Create short URL
  app.post('/shorten', async (req, res) => {
    try {
      const { url } = req.body;
      
      if (!url) {
        return res.status(400).json({ error: 'URL is required' });
      }

      // Validate URL format
      try {
        new URL(url);
      } catch {
        return res.status(400).json({ error: 'Invalid URL format' });
      }

      // Generate unique short code (check if exists)
      let shortCode;
      let exists = true;
      while (exists) {
        shortCode = generateShortCode();
        exists = await redisClient.exists(shortCode);
      }
      
      // Store in Redis with URL and metadata
      await redisClient.hSet(shortCode, {
        url: url,
        clicks: 0,
        created_at: new Date().toISOString()
      });
      
      // Optional: Set expiry (e.g., 30 days)
      // await redisClient.expire(shortCode, 30 * 24 * 60 * 60);

      const baseUrl = process.env.BASE_URL || `http://localhost:${port}`;

      res.json({
        short_url: `${baseUrl}/${shortCode}`,
        short_code: shortCode,
        original_url: url
      });
    } catch (error) {
      console.error('Error creating short URL:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Redirect to original URL
  app.get('/:shortCode', async (req, res) => {
    try {
      const { shortCode } = req.params;
      
      // Get URL from Redis
      const data = await redisClient.hGetAll(shortCode);
      
      if (!data || !data.url) {
        return res.status(404).json({ error: 'URL not found' });
      }
      
      // Increment click count
      await redisClient.hIncrBy(shortCode, 'clicks', 1);
      
      res.redirect(302, data.url);
    } catch (error) {
      console.error('Error redirecting:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Get stats for a short URL
  app.get('/stats/:shortCode', async (req, res) => {
    try {
      const { shortCode } = req.params;
      
      const data = await redisClient.hGetAll(shortCode);
      
      if (!data || !data.url) {
        return res.status(404).json({ error: 'URL not found' });
      }
      
      res.json({
        short_code: shortCode,
        original_url: data.url,
        clicks: parseInt(data.clicks || 0),
        created_at: data.created_at
      });
    } catch (error) {
      console.error('Error getting stats:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // List all short URLs (for admin/debugging)
  app.get('/admin/urls', async (req, res) => {
    try {
      const keys = await redisClient.keys('*');
      const urls = [];
      
      for (const key of keys) {
        if (key !== 'health' && !key.includes('*')) {
          const data = await redisClient.hGetAll(key);
          if (data.url) {
            urls.push({
              short_code: key,
              original_url: data.url,
              clicks: parseInt(data.clicks || 0)
            });
          }
        }
      }
      
      res.json(urls);
    } catch (error) {
      console.error('Error listing URLs:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  app.listen(port, () => {
    console.log(`🚀 URL Shortener running on http://localhost:${port}`);
    console.log(`📡 Redis: Ready`);
  });
}

startServer().catch(console.error);