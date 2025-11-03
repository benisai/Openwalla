// main/backend/routes/speedtest.js

const express = require('express');
const router = express.Router();
const { databases } = require('../database/database'); 
const speedtestDb = databases.speedtest;

// 🚀 UPDATED PATH: Import the scheduler service runner
const { runServerSpeedTest } = require('../services/speedtest/speedtestScheduler'); 

/**
 * POST /api/speedtest/save
 * Saves a single speed test result into the database.
 */
router.post('/save', (req, res) => {
    const { latency, download, upload, status } = req.body;
    
    // Simple input validation
    if (typeof latency !== 'number' || typeof download !== 'number' || typeof upload !== 'number') {
        return res.status(400).json({ error: 'Invalid or missing numerical speed test data.' });
    }

    const sql = `INSERT INTO speedtest_results (latency, download, upload, status) VALUES (?, ?, ?, ?)`;
    
    speedtestDb.run(sql, [latency, download, upload, status], function(err) {
        if (err) {
            console.error('DB Error: Could not insert speed test result:', err.message);
            return res.status(500).json({ error: 'Failed to save result to database.' });
        }
        res.status(200).json({ 
            message: 'Result saved successfully', 
            id: this.lastID 
        });
    });
});

/**
 * GET /api/speedtest/history
 * Fetches the last 7 successful speed test results for graph display.
 */
router.get('/history', (req, res) => {
    // Selects the last 7 successful tests, ordered newest to oldest
    const sql = `
        SELECT download, upload, latency, timestamp 
        FROM speedtest_results 
        WHERE status = 'finished' 
        ORDER BY timestamp DESC 
        LIMIT 7
    `;
    
    speedtestDb.all(sql, [], (err, rows) => {
        if (err) {
            console.error('DB Error: Could not fetch speed test history:', err.message);
            return res.status(500).json({ error: 'Failed to fetch history.' });
        }
        
        // Rows are returned newest-first, but graphs typically plot oldest-first, so we reverse the array.
        res.json(rows.reverse()); 
    });
});


/**
 * POST /api/speedtest/run-scheduled-test
 * Manually triggers the server-side speed test runner defined in the scheduler service.
 */
router.post('/run-scheduled-test', (req, res) => {
    // Runs the scheduled test logic asynchronously
    runServerSpeedTest(); 
    
    // Respond immediately to prevent the request from timing out
    res.status(200).json({ 
        message: 'Server-side speed test manually initiated. Check server logs for status.',
        note: 'The actual test runs asynchronously and saves results directly to the database.'
    });
});


module.exports = router;
