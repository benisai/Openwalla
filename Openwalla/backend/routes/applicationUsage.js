
const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

// Get application usage by device MAC address
router.get('/device/:mac', (req, res) => {
  const mac = req.params.mac;
  const uniqueDigest = req.query.unique_digest === 'true';
  
  // Query to get application usage data grouped by application name
  const appQuery = uniqueDigest
    ? `SELECT detected_app_name, SUM(total_bytes) as total_bytes 
       FROM application_usage 
       WHERE local_mac = ? 
       GROUP BY detected_app_name
       ORDER BY total_bytes DESC`
    : `SELECT detected_app_name, SUM(total_bytes) as total_bytes 
       FROM application_usage 
       WHERE local_mac = ? 
       GROUP BY detected_app_name
       ORDER BY total_bytes DESC`;
  
  databases.flows.all(appQuery, [mac], (err, appRows) => {
    if (err) {
      console.error('Error fetching application usage:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    res.json(appRows);
  });
});

// Get hourly application usage data for a specific device
router.get('/device/:mac/hourly', (req, res) => {
  const mac = req.params.mac;
  const hours = parseInt(req.query.hours || '24');
  
  // Create a time limit based on requested hours
  const timeLimit = new Date();
  timeLimit.setHours(timeLimit.getHours() - hours);
  const timeLimitString = timeLimit.toISOString();
  
  // Query to get hourly usage data
  const hourlyQuery = `
    SELECT 
      strftime('%H', timeperiod) as hour,
      SUM(total_bytes) as usage
    FROM application_usage 
    WHERE local_mac = ? 
    AND timeperiod > ?
    GROUP BY strftime('%H', timeperiod)
    ORDER BY hour
  `;
  
  databases.flows.all(hourlyQuery, [mac, timeLimitString], (err, hourRows) => {
    if (err) {
      console.error('Error fetching hourly application usage:', err);
      return res.status(500).json({ error: 'Database error' });
    }
    
    // Convert hour strings to numbers for the frontend
    const formattedData = hourRows.map(row => ({
      hour: parseInt(row.hour, 10),
      usage: row.usage
    }));
    
    res.json(formattedData);
  });
});

module.exports = router;
