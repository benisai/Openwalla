
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
 * - Flow digest information
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when the flow table is created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.serialize(() => {
      // Create stats_purge table
      db.run(`
        CREATE TABLE IF NOT EXISTS stats_purge (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timeinsert TEXT,
          type TEXT,
          digest TEXT,
          detection_packets INTEGER,
          last_seen_at INTEGER,
          local_bytes INTEGER,
          local_packets INTEGER,
          other_bytes INTEGER,
          other_packets INTEGER,
          total_bytes INTEGER,
          total_packets INTEGER,
          interface TEXT,
          internal INTEGER,
          reason TEXT
        )
      `);

      // Create flow table
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
          host_server_name TEXT,
          digest TEXT
        )
      `);

      // Create application_usage table with digest as PRIMARY unique identifier
      db.run(`
        CREATE TABLE IF NOT EXISTS application_usage (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timeinsert TEXT,
          local_mac TEXT,
          hostname TEXT,
          detected_app_name TEXT,
          timeperiod TEXT,
          digest TEXT UNIQUE,
          total_bytes INTEGER DEFAULT 0,
          upload_bytes INTEGER DEFAULT 0,
          download_bytes INTEGER DEFAULT 0,
          total_packets INTEGER DEFAULT 0,
          flow_count INTEGER DEFAULT 0,
          last_updated INTEGER
        )
      `, (err) => {
        if (err) {
          console.error('Error creating application_usage table:', err);
          reject(err);
          return;
        }

        // Create indices for application_usage
        db.run('CREATE INDEX IF NOT EXISTS idx_mac_time ON application_usage(local_mac, timeperiod)', (err) => {
          if (err) {
            console.error('Error creating idx_mac_time index:', err);
            reject(err);
            return;
          }

          db.run('CREATE INDEX IF NOT EXISTS idx_app_mac ON application_usage(detected_app_name, local_mac)', (err) => {
            if (err) {
              console.error('Error creating idx_app_mac index:', err);
              reject(err);
              return;
            }

            // Add primary index for digest
            db.run('CREATE UNIQUE INDEX IF NOT EXISTS idx_digest ON application_usage(digest)', (err) => {
              if (err) {
                console.error('Error creating idx_digest index:', err);
                reject(err);
                return;
              }
              resolve();
            });
          });
        });
      });
    });
  });
};
