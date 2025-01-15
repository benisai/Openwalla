const express = require('express');
const router = express.Router();
const { databases } = require('../database');

router.get('/', (req, res) => {
  const { type, last24h } = req.query;
  let sql = 'SELECT * FROM notifications WHERE (action IS NULL OR action = "none")';
  const params = [];

  if (type || last24h) {
    if (type) {
      sql += ' AND type = ?';
      params.push(type);
    }
    if (last24h) {
      sql += ' AND detect_time > ?';
      params.push(Date.now() - 24 * 60 * 60 * 1000);
    }
  }

  sql += ' ORDER BY detect_time DESC';

  databases.notifications.all(sql, params, (err, rows) => {
    if (err) {
      console.error('Error fetching notifications:', err);
      res.status(500).json({ error: 'Failed to fetch notifications' });
    } else {
      res.json(rows);
    }
  });
});

router.post('/:uuid/archive', (req, res) => {
  const { uuid } = req.params;
  
  databases.notifications.run(
    'UPDATE notifications SET action = ? WHERE uuid = ?',
    ['archived', uuid],
    (err) => {
      if (err) {
        console.error('Error archiving notification:', err);
        res.status(500).json({ error: 'Failed to archive notification' });
      } else {
        res.json({ success: true });
      }
    }
  );
});

module.exports = router;