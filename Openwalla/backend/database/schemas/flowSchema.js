/**
 * Flow Schema Definition
 * 
 * Manages network flow data including:
 * - Source/destination information
 * - Protocol and application details
 * - Network interface information
 * - Internal/external traffic designation
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when the flow table is created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.run(`
      CREATE TABLE IF NOT EXISTS flow (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timeinsert TEXT,
        hostname TEXT,
        local_ip TEXT,
        local_mac TEXT,
        fqdn TEXT,    
        dest_ip TEXT,
        dest_port INTEGER,
        dest_type TEXT,
        detected_protocol_name TEXT,
        detected_app_name TEXT,
        interface TEXT,
        internal INTEGER
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
};