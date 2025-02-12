
/**
 * Flow Schema Definition
 * 
 * Manages network flow data including:
 * - Source/destination information
 * - Protocol and application details
 * - Network interface information
 * - Internal/external traffic designation
 * - Risk scores and SSL information
 * - Category and detection information
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
        internal INTEGER,
        ndpi_risk_score INTEGER DEFAULT 0,
        ndpi_risk_score_client INTEGER DEFAULT 0,
        ndpi_risk_score_server INTEGER DEFAULT 0,
        client_sni TEXT,
        category_application INTEGER DEFAULT 0,
        category_domain INTEGER DEFAULT 0,
        category_protocol INTEGER DEFAULT 0,
        detected_application INTEGER DEFAULT 0,
        detected_protocol INTEGER DEFAULT 0,
        detection_guessed INTEGER DEFAULT 0,
        dns_host_name TEXT,
        host_server_name TEXT
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
};
