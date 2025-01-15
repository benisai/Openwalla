const express = require('express');
const router = express.Router();
const { databases } = require('../database');

// Get all ping stats for the last 24 hours
router.get('/last24hours', (req, res) => {
  const sql = `
    SELECT * FROM pingstats 
    WHERE datetime(date || ' ' || time) >= datetime('now', '-1 day')
    ORDER BY date DESC, time DESC
  `;
  
  databases.pingStats.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Error fetching ping stats:', err);
      res.status(500).json({ error: 'Failed to fetch ping stats' });
      return;
    }
    res.json(rows);
  });
});

// Get ping stats for a specific date range
router.get('/range', (req, res) => {
  const { startDate, endDate } = req.query;
  
  if (!startDate || !endDate) {
    res.status(400).json({ error: 'Start date and end date are required' });
    return;
  }

  const sql = `
    SELECT * FROM pingstats 
    WHERE datetime(date || ' ' || time) BETWEEN datetime(?) AND datetime(?)
    ORDER BY date DESC, time DESC
  `;
  
  databases.pingStats.all(sql, [startDate, endDate], (err, rows) => {
    if (err) {
      console.error('Error fetching ping stats:', err);
      res.status(500).json({ error: 'Failed to fetch ping stats' });
      return;
    }
    res.json(rows);
  });
});

// Add new route for summary stats
router.get('/summary', (req, res) => {
  const sql = `
    SELECT 
      MAX(latency) as maxLatency,
      MAX(packet_loss) as maxPacketLoss
    FROM pingstats 
    WHERE timestamp >= datetime('now', '-24 hours')
  `;

  databases.pingStats.get(sql, [], (err, row) => {
    if (err) {
      console.error('Error fetching ping stats summary:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json({
        maxLatency: Math.round(row?.maxLatency || 0),
        maxPacketLoss: Math.round(row?.maxPacketLoss || 0)
      });
    }
  });
});

module.exports = router;