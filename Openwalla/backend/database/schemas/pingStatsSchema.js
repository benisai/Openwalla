/**
 * Ping Statistics Schema Definition
 * 
 * Stores network ping statistics including:
 * - Latency measurements
 * - Packet loss data
 * - Timestamp information
 * - Connection status and errors
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when the pingstats table is created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.run(`
      CREATE TABLE IF NOT EXISTS pingstats (
        uuid TEXT PRIMARY KEY,
        ip TEXT,
        ms REAL,
        max_latency REAL,
        median_latency REAL,
        packetloss REAL,
        date TEXT,
        time TEXT,
        timestamp INTEGER,
        target_ip TEXT,
        latency REAL,
        packet_loss REAL,
        status TEXT,
        error_message TEXT
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
};