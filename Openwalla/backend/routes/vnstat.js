const express = require('express');
const router = express.Router();
const { databases } = require('../database');

router.get('/daily', (req, res) => {
  const today = new Date();
  const sql = `
    SELECT year, month, day, rx, tx, interface_name 
    FROM daily 
    WHERE year = ? AND month = ?
    ORDER BY day ASC
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat daily data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

router.get('/monthly', (req, res) => {
  const today = new Date();
  const sql = `
    SELECT year, month, rx, tx, interface_name
    FROM monthly 
    WHERE year = ? AND month = ?
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat monthly data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

router.get('/hourly', (req, res) => {
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  
  const sql = `
    WITH unique_hours AS (
      SELECT DISTINCT year, month, day, hour, rx, tx, interface_name, timestamp,
             ROW_NUMBER() OVER (PARTITION BY year, month, day, hour ORDER BY timestamp DESC) as rn
      FROM hourly 
      WHERE (year = ? AND month = ? AND day = ?) OR 
            (year = ? AND month = ? AND day = ?)
    )
    SELECT year, month, day, hour, rx, tx, interface_name, timestamp
    FROM unique_hours 
    WHERE rn = 1
    ORDER BY timestamp DESC 
    LIMIT 12
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1,
    today.getDate(),
    yesterday.getFullYear(),
    yesterday.getMonth() + 1,
    yesterday.getDate()
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat hourly data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows.reverse());
    }
  });
});

module.exports = router;