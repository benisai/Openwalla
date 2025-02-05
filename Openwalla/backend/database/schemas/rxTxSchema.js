/**
 * RX/TX Schema Definition
 * 
 * Manages real-time traffic data including:
 * - Device identification (MAC, IP)
 * - Timestamp information
 * - Traffic counters (RX_Diff, TX_Diff)
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when the rx_tx table is created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.run(`
      CREATE TABLE IF NOT EXISTS rx_tx (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mac TEXT NOT NULL,
        ip TEXT,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        hour INTEGER,
        minute INTEGER,
        second INTEGER,
        rx_diff INTEGER,
        tx_diff INTEGER,
        timestamp INTEGER
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
};
