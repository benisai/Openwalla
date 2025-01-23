const express = require('express');
const router = express.Router();
const { databases } = require('../database');

router.get('/', (req, res) => {
  const { type, last24h, includeArchived } = req.query;
  let sql = 'SELECT * FROM notifications';
  const params = [];
  const conditions = [];

  if (type) {
    conditions.push('type = ?');
    params.push(type);
  }

  if (last24h) {
    conditions.push('detect_time > ?');
    params.push(Date.now() - 24 * 60 * 60 * 1000);
  }

  // Only include archived notifications if explicitly requested
  if (!includeArchived) {
    conditions.push('(action IS NULL OR action != ?)');
    params.push('archived');
  }

  if (conditions.length > 0) {
    sql += ' WHERE ' + conditions.join(' AND ');
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

// New endpoint for timeline notifications that always includes archived items
router.get('/timeline', (req, res) => {
  const sql = `
    SELECT * FROM notifications 
    WHERE type = 'internet_monitor' 
    AND detect_time > ? 
    ORDER BY detect_time DESC
  `;
  
  const params = [Date.now() - 24 * 60 * 60 * 1000];

  databases.notifications.all(sql, params, (err, rows) => {
    if (err) {
      console.error('Error fetching timeline notifications:', err);
      res.status(500).json({ error: 'Failed to fetch timeline notifications' });
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