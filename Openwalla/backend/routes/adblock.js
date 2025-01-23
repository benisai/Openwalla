const express = require('express');
const router = express.Router();
const { databases } = require('../database');
const AdblockService = require('../services/AdblockService');

// Fetch and update adblock data
router.post('/refresh', async (req, res) => {
  try {
    const data = await AdblockService.fetchAndParseAdblockData();
    res.json({ message: 'Adblock data refreshed successfully', data });
  } catch (error) {
    console.error('Error refreshing adblock data:', error);
    res.status(500).json({ error: 'Failed to refresh adblock data' });
  }
});

// Get top clients
router.get('/top-clients', (req, res) => {
  databases.adblock.all('SELECT * FROM adblock_top_clients ORDER BY query_count DESC', [], (err, rows) => {
    if (err) {
      console.error('Error fetching top clients:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

// Get top domains
router.get('/top-domains', (req, res) => {
  databases.adblock.all('SELECT * FROM adblock_top_domains ORDER BY query_count DESC', [], (err, rows) => {
    if (err) {
      console.error('Error fetching top domains:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

// Get top blocked domains
router.get('/blocked-domains', (req, res) => {
  databases.adblock.all('SELECT * FROM adblock_blocked_domains ORDER BY block_count DESC', [], (err, rows) => {
    if (err) {
      console.error('Error fetching blocked domains:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

// Get recent DNS queries
router.get('/dns-queries', (req, res) => {
  const limit = req.query.limit || 100;
  databases.adblock.all(
    'SELECT * FROM adblock_dns_queries ORDER BY query_date DESC, query_time DESC LIMIT ?',
    [limit],
    (err, rows) => {
      if (err) {
        console.error('Error fetching DNS queries:', err);
        res.status(500).json({ error: 'Database error' });
      } else {
        res.json(rows);
      }
    }
  );
});

module.exports = router;