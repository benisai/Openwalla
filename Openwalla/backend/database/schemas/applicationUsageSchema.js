
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.serialize(() => {
      // Create application_usage table
      db.run(`
        CREATE TABLE IF NOT EXISTS application_usage (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_mac TEXT,
          hostname TEXT,
          detected_app_name TEXT,
          timeperiod TEXT,  -- Format: YYYY-MM-DD HH:00:00
          total_bytes INTEGER DEFAULT 0,
          upload_bytes INTEGER DEFAULT 0,
          download_bytes INTEGER DEFAULT 0,
          total_packets INTEGER DEFAULT 0,
          flow_count INTEGER DEFAULT 0,
          digest TEXT,
          last_updated INTEGER,
          UNIQUE(local_mac, detected_app_name, timeperiod, digest)
        )
      `, (err) => {
        if (err) {
          console.error('Error creating application_usage table:', err);
          reject(err);
          return;
        }

        // Create indices
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
            resolve();
          });
        });
      });
    });
  });
};
