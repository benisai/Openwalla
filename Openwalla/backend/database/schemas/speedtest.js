// backend/database/schemas/speedtest.js

const createSpeedTestTable = `
CREATE TABLE IF NOT EXISTS speedtest_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    latency REAL NOT NULL,
    download REAL NOT NULL,
    upload REAL NOT NULL,
    status TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
`;

/**
 * Initializes the Speed Test database table.
 * @param {import('sqlite3').Database} db - The database connection object.
 */
function initializeSpeedTest(db) {
    return new Promise((resolve, reject) => {
        db.exec(createSpeedTestTable, (err) => {
            if (err) {
                console.error('Error creating speedtest_results table:', err.message);
                reject(err);
            } else {
                console.log('✅ Speed test table initialized.');
                resolve();
            }
        });
    });
}

module.exports = initializeSpeedTest;
