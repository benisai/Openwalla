const { databases } = require('../connections');

async function initializePingStatsSchema() {
  return new Promise((resolve, reject) => {
    databases.pingStats.run(`
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
}

module.exports = { initializePingStatsSchema };