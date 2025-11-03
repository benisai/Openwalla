const cron = require('node-cron');
// The database import is relative to the scheduler service file location:
// main/backend/services/speedtest/speedtestScheduler.js -> ../../database/database
const { databases } = require('../../database/database');
const speedtestDb = databases.speedtest;
const configsDb = databases.configs; // 👈 Accessing the configs database

function runServerSpeedTest() {
    console.log('--- Running Scheduled Speed Test ---');
    
    // Placeholder for actual server-side speed test execution.
    const mockResult = {
        latency: Math.floor(Math.random() * 20) + 10, // 10-30ms
        download: Math.floor(Math.random() * 100000000) + 50000000, // 50-150 Mbps
        upload: Math.floor(Math.random() * 10000000) + 20000000,   // 20-30 Mbps
        status: 'finished'
    };
    
    // Simulate the save operation
    const INSERT_SQL = `INSERT INTO speedtest_results (latency, download, upload, status) VALUES (?, ?, ?, ?)`;
        
    speedtestDb.run(INSERT_SQL, [mockResult.latency, mockResult.download, mockResult.upload, mockResult.status], function(insertErr) {
        if (insertErr) {
            console.error('Scheduler DB Error: Could not insert scheduled speed test result:', insertErr.message);
        } else {
            console.log(`✅ Scheduled test saved with ID ${this.lastID}. Latency: ${mockResult.latency}ms`);
        }
    });
}


/**
 * Schedules a nightly speed test using cron based on the 'speedtest_run' config key.
 * The time is expected to be in 24-hour format (e.g., '02:00').
 */
const startScheduler = () => {
    
    // 1. Fetch the scheduled time from the configs database
    configsDb.get("SELECT value FROM configs WHERE key = ?", ['speedtest_run'], (err, row) => {
        let scheduleTime = '02:00'; // Default to 2:00 AM
        
        if (err) {
            console.error('Scheduler DB Error: Could not read speedtest_run from configs, using default (02:00):', err.message);
        } else if (row && row.value) {
            // Found a configured time
            scheduleTime = row.value.trim();
        } else {
             // 2. If the key is not found, insert the default '02:00'
            const defaultSql = `INSERT OR IGNORE INTO configs (key, value) VALUES (?, ?)`;
            configsDb.run(defaultSql, ['speedtest_run', '02:00'], (insertErr) => {
                 if (insertErr) {
                    console.error('Scheduler DB Error: Could not insert default speedtest_run config:', insertErr.message);
                 } else {
                    console.log("Config 'speedtest_run' initialized to '02:00'.");
                 }
            });
        }
        
        // 3. Convert 'HH:MM' (e.g., '02:00') to cron format ('MM HH * * *')
        const [hour, minute] = scheduleTime.split(':');
        const cronSchedule = `${parseInt(minute)} ${parseInt(hour)} * * *`; 
        
        console.log(`⏳ Speed Test Scheduler initialized. Next run scheduled for ${scheduleTime} daily (${cronSchedule}).`);
        
        cron.schedule(cronSchedule, () => {
            console.log(`\n======================================================`);
            console.log(`⏰ Scheduled speed test triggered at ${new Date().toLocaleString()}`);
            runServerSpeedTest();
            console.log(`======================================================`);
        }, {
            scheduled: true,
            timezone: "America/Los_Angeles" // Ensure this matches your desired server timezone
        });
    });
};

module.exports = {
    startScheduler,
    runServerSpeedTest
};
