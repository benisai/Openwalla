const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

router.get('/count/24h', (req, res) => {
  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  
  //console.log('Fetching flows from:', twentyFourHoursAgo);
  
  const sql = `
    SELECT COUNT(*) as count 
    FROM flow 
    WHERE datetime(timeinsert) >= datetime(?)
  `;
  
  databases.flows.get(sql, [twentyFourHoursAgo], (err, row) => {
    if (err) {
      console.error('Error getting flow count:', err);
      res.status(500).json({ error: 'Failed to get flow count', details: err.message });
      return;
    }
    //console.log('Flow count result:', row);
    res.json({ count: row ? row.count : 0 });
  });
});

router.get('/blocked/count/24h', (req, res) => {
  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  
  //console.log('Fetching blocked flows from:', twentyFourHoursAgo);
  
  const sql = `
    SELECT COUNT(*) as count 
    FROM blocked_flow 
    WHERE datetime(timeinsert) >= datetime(?)
  `;
  
  databases.blockedFlows.get(sql, [twentyFourHoursAgo], (err, row) => {
    if (err) {
      console.error('Error getting blocked flow count:', err);
      res.status(500).json({ error: 'Failed to get blocked flow count', details: err.message });
      return;
    }
    //console.log('Blocked flow count result:', row);
    res.json({ count: row ? row.count : 0 });
  });
});

router.get('/top-clients/24h', (req, res) => {
  const sql = `
    SELECT local_mac, COUNT(*) as count 
    FROM flow 
    WHERE datetime(timeinsert) >= datetime('now', '-24 hours')
    AND dest_port = 443
    GROUP BY local_mac 
    ORDER BY count DESC 
    LIMIT 10
  `;
  
  //console.log('Fetching top HTTPS clients for last 24 hours');
  
  databases.flows.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Error getting top clients:', err);
      res.status(500).json({ error: 'Failed to get top clients', details: err.message });
      return;
    }
    
    // Get device information for each MAC address from the correct database and table
    const devicePromises = rows.map(row => {
      return new Promise((resolve, reject) => {
        databases.devices.get(
          'SELECT hostname FROM clients WHERE mac = ?',
          [row.local_mac],
          (err, device) => {
            if (err) reject(err);
            resolve({
              ...row,
              name: device ? device.hostname : 'Unknown Device',
            });
          }
        );
      });
    });

    Promise.all(devicePromises)
      .then(enrichedRows => {
        //console.log('Top HTTPS clients with device names:', enrichedRows);
        res.json(enrichedRows);
      })
      .catch(error => {
        console.error('Error enriching client data:', error);
        res.status(500).json({ error: 'Failed to enrich client data', details: error.message });
      });
  });
});

router.get('/recent', (req, res) => {
  const hours = parseInt(req.query.hours) || 1;
  const hoursAgo = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
  
  //console.log(`Fetching flows from last ${hours} hours:`, hoursAgo);
  
  const sql = `
    SELECT * FROM flow 
    WHERE datetime(timeinsert) >= datetime(?) 
    ORDER BY timeinsert DESC
  `;
  
  databases.flows.all(sql, [hoursAgo], (err, rows) => {
    if (err) {
      console.error('Error getting flows:', err);
      res.status(500).json({ error: 'Failed to get flows', details: err.message });
      return;
    }
    //console.log(`Retrieved ${rows.length} flows`);
    res.json(rows);
  });
});

router.get('/blocked/recent', (req, res) => {
  const hours = parseInt(req.query.hours) || 1;
  const hoursAgo = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
  
  //console.log(`Fetching blocked flows from last ${hours} hours:`, hoursAgo);
  
  const sql = `
    SELECT * FROM blocked_flow 
    WHERE datetime(timeinsert) >= datetime(?) 
    ORDER BY timeinsert DESC
  `;
  
  databases.blockedFlows.all(sql, [hoursAgo], (err, rows) => {
    if (err) {
      console.error('Error getting blocked flows:', err);
      res.status(500).json({ error: 'Failed to get blocked flows', details: err.message });
      return;
    }
    //console.log(`Retrieved ${rows.length} blocked flows`);
    res.json(rows);
  });
});

router.get('/count/device/:mac', (req, res) => {
  const sql = `
    SELECT COUNT(*) as count 
    FROM flow 
    WHERE local_mac = ?
  `;
  
  databases.flows.get(sql, [req.params.mac.toLowerCase()], (err, row) => {
    if (err) {
      console.error('Error getting device flow count:', err);
      res.status(500).json({ error: 'Failed to get device flow count', details: err.message });
      return;
    }
    res.json({ count: row ? row.count : 0 });
  });
});

router.get('/device/:mac', (req, res) => {
  const hours = parseInt(req.query.hours) || 1;
  const hoursAgo = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
  
  const sql = `
    SELECT * FROM flow 
    WHERE local_mac = ? 
    AND datetime(timeinsert) >= datetime(?) 
    ORDER BY timeinsert DESC
  `;
  
  databases.flows.all(sql, [req.params.mac.toLowerCase(), hoursAgo], (err, rows) => {
    if (err) {
      console.error('Error getting device flows:', err);
      res.status(500).json({ error: 'Failed to get device flows', details: err.message });
      return;
    }
    res.json(rows);
  });
});

router.get('/device/:mac/top-fqdn', (req, res) => {
  const sql = `
    SELECT fqdn, COUNT(*) as count 
    FROM flow 
    WHERE local_mac = ? 
    AND fqdn IS NOT NULL
    AND fqdn != ''
    AND datetime(timeinsert) >= datetime('now', '-24 hours')
    GROUP BY fqdn 
    ORDER BY count DESC 
    LIMIT 10
  `;
  
  //console.log('Executing top FQDN query for MAC:', req.params.mac.toLowerCase());
  
  databases.flows.all(sql, [req.params.mac.toLowerCase()], (err, rows) => {
    if (err) {
      console.error('Error getting top FQDNs:', err);
      res.status(500).json({ error: 'Failed to get top FQDNs', details: err.message });
      return;
    }
    
    // Log the raw results
    //console.log('Raw FQDN results:', rows);
    
    // Additional validation of results
    const validRows = rows.filter(row => row.fqdn && row.fqdn.trim() !== '');
    //console.log('Filtered FQDN results:', validRows);
    
    res.json(validRows);
  });
});

router.get('/device/:mac/top-dest-ips', (req, res) => {
  const sql = `
    SELECT dest_ip, COUNT(*) as count 
    FROM flow 
    WHERE local_mac = ? 
    AND dest_ip IS NOT NULL
    AND dest_ip != ''
    AND datetime(timeinsert) >= datetime('now', '-24 hours')
    GROUP BY dest_ip 
    ORDER BY count DESC 
    LIMIT 10
  `;
  
  //console.log('Executing top dest IPs query for MAC:', req.params.mac.toLowerCase());
  
  databases.flows.all(sql, [req.params.mac.toLowerCase()], (err, rows) => {
    if (err) {
      console.error('Error getting top destination IPs:', err);
      res.status(500).json({ error: 'Failed to get top destination IPs', details: err.message });
      return;
    }
    
    // Log the raw results
    //console.log('Raw dest IP results:', rows);
    
    // Additional validation of results
    const validRows = rows.filter(row => row.dest_ip && row.dest_ip.trim() !== '');
    //console.log('Filtered dest IP results:', validRows);
    
    res.json(validRows);
  });
});

router.get('/device/:mac/top-applications', (req, res) => {
  const sql = `
    SELECT detected_app_name, COUNT(*) as count 
    FROM flow 
    WHERE local_mac = ? 
    AND detected_app_name IS NOT NULL
    AND detected_app_name != ''
    AND datetime(timeinsert) >= datetime('now', '-24 hours')
    GROUP BY detected_app_name 
    ORDER BY count DESC 
    LIMIT 10
  `;
  
  //console.log('Executing top applications query for MAC:', req.params.mac.toLowerCase());
  
  databases.flows.all(sql, [req.params.mac.toLowerCase()], (err, rows) => {
    if (err) {
      console.error('Error getting top applications:', err);
      res.status(500).json({ error: 'Failed to get top applications', details: err.message });
      return;
    }
    
    //console.log('Raw application results:', rows);
    
    const validRows = rows.filter(row => row.detected_app_name && row.detected_app_name.trim() !== '');
    //console.log('Filtered application results:', validRows);
    
    res.json(validRows);
  });
});

router.get('/usage/:digest', (req, res) => {
  const { digest } = req.params;
  
  if (!digest) {
    return res.status(400).json({ error: 'Digest parameter is required' });
  }
  
  //console.log('Fetching flow usage for digest:', digest);
  
  const sql = `
    SELECT 
      SUM(local_bytes) as localBytes, 
      SUM(other_bytes) as otherBytes,
      SUM(local_bytes + other_bytes) as totalBytes
    FROM stats_purge 
    WHERE digest = ?
  `;
  
  // Log the SQL query for debugging
  console.log('Executing SQL query:', sql, 'with digest:', digest);
  
  databases.flows.get(sql, [digest], (err, row) => {
    if (err) {
      console.error('Error fetching flow usage data:', err);
      return res.status(500).json({ error: 'Failed to fetch flow usage data', details: err.message });
    }
    
    console.log('Raw database result:', row);
    
    if (!row || (row.localBytes === null && row.otherBytes === null && row.totalBytes === null)) {
      //console.log('No usage data found for digest:', digest);
      return res.json({ localBytes: 0, otherBytes: 0, totalBytes: 0 });
    }
    
    console.log('Flow usage data for digest:', digest, row);
    res.json({
      localBytes: row.localBytes || 0,
      otherBytes: row.otherBytes || 0,
      totalBytes: row.totalBytes || 0
    });
  });
});

module.exports = router;
