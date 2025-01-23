const express = require('express');
const router = express.Router();
const { databases } = require('../database');
const { getEnvConfig } = require('../utils/config');

const DEFAULT_CONFIG = getEnvConfig();

router.get('/', (req, res) => {
  databases.openwalla.all('SELECT key, value FROM configs', [], (err, rows) => {
    if (err) {
      console.error('Error reading config from database:', err);
      res.status(500).json({ error: 'Failed to read config' });
    } else {
      const config = { ...DEFAULT_CONFIG };
      rows.forEach(row => {
        config[row.key] = row.value;
      });
      res.json(config);
    }
  });
});

router.post('/', (req, res) => {
  const updates = req.body;
  const stmt = databases.openwalla.prepare('INSERT OR REPLACE INTO configs (key, value) VALUES (?, ?)');
  
  try {
    Object.entries(updates).forEach(([key, value]) => {
      stmt.run(key, value);
    });
    
    stmt.finalize(async (err) => {
      if (err) {
        console.error('Error saving config to database:', err);
        res.status(500).json({ error: 'Failed to save config' });
      } else {
        databases.openwalla.all('SELECT key, value FROM configs', [], async (err, rows) => {
          if (err) {
            res.status(500).json({ error: 'Failed to read updated config' });
          } else {
            const newConfig = { ...DEFAULT_CONFIG };
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