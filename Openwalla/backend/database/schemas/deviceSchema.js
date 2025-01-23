const { databases } = require('../connections');

async function initializeDeviceSchema() {
  const promises = [];

  promises.push(new Promise((resolve, reject) => {
    databases.devices.run(`
      CREATE TABLE IF NOT EXISTS clients (
        mac TEXT PRIMARY KEY,
        hostname TEXT NOT NULL,
        ip TEXT,
        timeinserted INTEGER,
        source TEXT,
        new INTEGER DEFAULT 1
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  promises.push(new Promise((resolve, reject) => {
    databases.devices.run(`
      CREATE TABLE IF NOT EXISTS nlbw (
        mac TEXT PRIMARY KEY,
        ip TEXT,
        connections INTEGER DEFAULT 0,
        dl_speed INTEGER DEFAULT 0,
        ul_speed INTEGER DEFAULT 0,
        total_download INTEGER DEFAULT 0,
        total_upload INTEGER DEFAULT 0,
        FOREIGN KEY (mac) REFERENCES clients(mac)
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  promises.push(new Promise((resolve, reject) => {
    databases.devices.run(`
      CREATE TABLE IF NOT EXISTS device_types (
        mac TEXT PRIMARY KEY,
        icon_type TEXT DEFAULT 'computer',
        FOREIGN KEY (mac) REFERENCES clients(mac)
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  return Promise.all(promises);
}

module.exports = { initializeDeviceSchema };