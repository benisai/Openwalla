
const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

// Login endpoint
router.post('/login', (req, res) => {
  const { username, password } = req.body;
  
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required' });
  }

  // Get auth credentials from configs database
  databases.configs.all('SELECT key, value FROM configs WHERE key IN (?, ?)', 
    ['auth_username', 'auth_password'],
    (err, rows) => {
      if (err) {
        console.error('Database error during login:', err);
        return res.status(500).json({ error: 'Internal server error' });
      }

      const config = {};
      rows.forEach(row => {
        config[row.key] = row.value;
      });

      if (config.auth_username === username && config.auth_password === password) {
        // Simple session token (in production, use proper JWT or session management)
        const token = Buffer.from(`${username}:${Date.now()}`).toString('base64');
        res.json({ 
          success: true, 
          token,
          user: { username }
        });
      } else {
        res.status(401).json({ error: 'Invalid username or password' });
      }
    }
  );
});

// Verify token endpoint
router.post('/verify', (req, res) => {
  const { token } = req.body;
  
  if (!token) {
    return res.status(400).json({ error: 'Token is required' });
  }

  try {
    // Simple token verification (in production, use proper JWT verification)
    const decoded = Buffer.from(token, 'base64').toString('utf-8');
    const [username, timestamp] = decoded.split(':');
    
    // Check if token is not older than 24 hours
    const tokenAge = Date.now() - parseInt(timestamp);
    const maxAge = 24 * 60 * 60 * 1000; // 24 hours
    
    if (tokenAge > maxAge) {
      return res.status(401).json({ error: 'Token expired' });
    }

    // Verify username exists in configs
    databases.configs.get(
      'SELECT value FROM configs WHERE key = ?',
      ['auth_username'],
      (err, row) => {
        if (err) {
          console.error('Database error during token verification:', err);
          return res.status(500).json({ error: 'Internal server error' });
        }

        if (row && row.value === username) {
          res.json({ 
            success: true, 
            user: { username }
          });
        } else {
          res.status(401).json({ error: 'Invalid token' });
        }
      }
    );
  } catch (error) {
    console.error('Token verification error:', error);
    res.status(401).json({ error: 'Invalid token format' });
  }
});

module.exports = router;
