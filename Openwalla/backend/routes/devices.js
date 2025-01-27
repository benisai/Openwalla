const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

// Get all devices with their network stats
router.get('/', (req, res) => {
  const sql = `
    SELECT 
      c.mac,
      c.hostname,
      c.ip,
      c.timeinserted,
      c.source,
      c.new,
      n.dl_speed,
      n.ul_speed,
      n.total_download,
      n.total_upload
    FROM clients c
    LEFT JOIN nlbw n ON c.mac = n.mac
    ORDER BY c.hostname
  `;
  
  databases.devices.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Error getting devices:', err);
      res.status(500).json({ error: 'Failed to get devices', details: err.message });
      return;
    }
    res.json(rows || []);
  });
});

// Check if device is active (has flows in last minute)
router.get('/active/:mac', (req, res) => {
  const oneMinuteAgo = new Date(Date.now() - 60 * 1000).toISOString();
  
  const sql = `
    SELECT COUNT(*) as count 
    FROM flow 
    WHERE local_mac = ? 
    AND datetime(timeinsert) >= datetime(?)
  `;
  
  databases.flows.get(sql, [req.params.mac.toLowerCase(), oneMinuteAgo], (err, row) => {
    if (err) {
      console.error('Error checking device activity:', err);
      res.status(500).json({ error: 'Failed to check device activity', details: err.message });
      return;
    }
    res.json({ isActive: row.count > 0 });
  });
});

// Get device by MAC address
router.get('/:mac', (req, res) => {
  const sql = `
    SELECT 
      c.mac,
      c.hostname,
      c.ip,
      c.timeinserted,
      c.source,
      c.new,
      n.dl_speed,
      n.ul_speed,
      n.total_download,
      n.total_upload
    FROM clients c
    LEFT JOIN nlbw n ON c.mac = n.mac
    WHERE c.mac = ?
  `;
  
  databases.devices.get(sql, [req.params.mac.toLowerCase()], (err, row) => {
    if (err) {
      console.error('Error getting device:', err);
      res.status(500).json({ error: 'Failed to get device', details: err.message });
      return;
    }
    if (!row) {
      res.status(404).json({ error: 'Device not found' });
      return;
    }
    res.json(row);
  });
});

// Update device hostname
router.put('/:mac/hostname', (req, res) => {
  const { hostname } = req.body;
  
  if (!hostname) {
    res.status(400).json({ error: 'Hostname is required' });
    return;
  }

  const sql = `
    UPDATE clients 
    SET hostname = ?
    WHERE mac = ?
  `;
  
  databases.devices.run(sql, [hostname, req.params.mac.toLowerCase()], function(err) {
    if (err) {
      console.error('Error updating hostname:', err);
      res.status(500).json({ error: 'Failed to update hostname', details: err.message });
      return;
    }
    if (this.changes === 0) {
      res.status(404).json({ error: 'Device not found' });
      return;
    }
    res.json({ message: 'Hostname updated successfully' });
  });
});

// Get device type
router.get('/:mac/type', (req, res) => {
  const sql = `
    SELECT icon_type 
    FROM device_types 
    WHERE mac = ?
  `;
  
  databases.devices.get(sql, [req.params.mac.toLowerCase()], (err, row) => {
    if (err) {
      console.error('Error getting device type:', err);
      res.status(500).json({ error: 'Failed to get device type', details: err.message });
      return;
    }
    res.json({ type: row?.icon_type || 'computer' });
  });
});

// Update device type
router.put('/:mac/type', (req, res) => {
  const { type } = req.body;
  
  if (!type) {
    res.status(400).json({ error: 'Type is required' });
    return;
  }

  const sql = `
    INSERT OR REPLACE INTO device_types (mac, icon_type)
    VALUES (?, ?)
  `;
  
  databases.devices.run(sql, [req.params.mac.toLowerCase(), type], function(err) {
    if (err) {
      console.error('Error updating device type:', err);
      res.status(500).json({ error: 'Failed to update device type', details: err.message });
      return;
    }
    res.json({ message: 'Device type updated successfully' });
  });
});

module.exports = router;
