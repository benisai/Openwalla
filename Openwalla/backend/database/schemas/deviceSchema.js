/**
 * Device Schema Definition
 * 
 * This schema manages device-related tables:
 * - clients: Stores basic device information like MAC address, hostname, IP
 * - device_types: Maps devices to their icon types for UI representation
 * - nlbw: Stores network bandwidth statistics for each device
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when all tables are created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    // Create the clients table
    db.run(`
      CREATE TABLE IF NOT EXISTS clients (
        mac TEXT PRIMARY KEY,
        hostname TEXT NOT NULL,
        ip TEXT,
        timeinserted INTEGER,
        source TEXT,
        new INTEGER DEFAULT 1
      )
    `, [], (err) => {
      if (err) {
        reject(err);
      } else {
        // Create the device_types table
        db.run(`
          CREATE TABLE IF NOT EXISTS device_types (
            mac TEXT PRIMARY KEY,
            icon_type TEXT DEFAULT 'computer',
            FOREIGN KEY (mac) REFERENCES clients(mac)
          )
        `, [], (err) => {
          if (err) {
            reject(err);
          } else {
            // Create the nlbw table
            db.run(`
              CREATE TABLE IF NOT EXISTS nlbw (
                mac TEXT PRIMARY KEY,
                ip TEXT,
                connections INTEGER DEFAULT 0,
                dl_speed INTEGER DEFAULT 0,
                ul_speed INTEGER DEFAULT 0,
                total_download INTEGER DEFAULT 0,
                total_upload INTEGER DEFAULT 0,
                FOREIGN KEY (mac) REFERENCES clients(mac) ON DELETE CASCADE
              )
            `, [], (err) => {
              if (err) {
                reject(err);
              } else {
                resolve();
              }
            });
          }
        });
      }
    });
  });
};