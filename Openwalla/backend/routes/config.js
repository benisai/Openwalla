
const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

// Get config
router.get('/', (req, res) => {
  databases.configs.all('SELECT key, value FROM configs', [], (err, rows) => {
    if (err) {
      console.error('Error reading config from database:', err);
      res.status(500).json({ error: 'Failed to read config' });
    } else {
      const config = {};
      rows.forEach(row => {
        config[row.key] = row.value;
      });
      res.json(config);
    }
  });
});

// Update config
router.post('/', (req, res) => {
  const updates = req.body;
  const stmt = databases.configs.prepare('INSERT OR REPLACE INTO configs (key, value) VALUES (?, ?)');
  
  try {
    Object.entries(updates).forEach(([key, value]) => {
      // Skip auth fields for config table, they'll be handled separately
      if (key !== 'auth_username' && key !== 'auth_password') {
        stmt.run(key, value);
      }
    });
    
    stmt.finalize(async (err) => {
      if (err) {
        console.error('Error saving config to database:', err);
        res.status(500).json({ error: 'Failed to save config' });
      } else {
        // Handle auth_username and auth_password updates
        if (updates.auth_username) {
          databases.configs.run('INSERT OR REPLACE INTO configs (key, value) VALUES (?, ?)', 
            ['auth_username', updates.auth_username]);
        }

        if (updates.auth_password) {
          databases.configs.run('INSERT OR REPLACE INTO configs (key, value) VALUES (?, ?)', 
            ['auth_password', updates.auth_password]);
        }

        // Get updated config
        databases.configs.all('SELECT key, value FROM configs', [], (err, rows) => {
          if (err) {
            res.status(500).json({ error: 'Failed to read updated config' });
          } else {
            const newConfig = {};
            rows.forEach(row => {
              newConfig[row.key] = row.value;
            });
            res.json(newConfig);
          }
        });
      }
    });
  } catch (error) {
    console.error('Error processing config updates:', error);
    res.status(500).json({ error: 'Failed to save config' });
  }
});

module.exports = router;
