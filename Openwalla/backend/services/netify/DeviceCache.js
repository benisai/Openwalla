const { databases } = require('../../database/database');

class DeviceCache {
  constructor() {
    this.cache = new Map();
    this.CACHE_REFRESH_INTERVAL = 5 * 60 * 1000; // 5 minutes
  }

  async loadCache() {
    const sql = `
      SELECT mac, hostname, ip
      FROM clients
    `;
    
    return new Promise((resolve, reject) => {
      databases.devices.all(sql, [], (err, rows) => {
        if (err) {
          console.error('Error loading device cache:', err);
          reject(err);
        } else {
          this.cache.clear();
          rows.forEach(row => {
            this.cache.set(row.mac.toLowerCase(), {
              hostname: row.hostname,
              ip: row.ip
            });
          });
          resolve();
        }
      });
    });
  }

  startRefreshInterval() {
    this.loadCache();
    setInterval(() => {
      this.loadCache();
    }, this.CACHE_REFRESH_INTERVAL);
  }

  get(mac) {
    return this.cache.get(mac.toLowerCase());
  }

  set(mac, data) {
    this.cache.set(mac.toLowerCase(), data);
  }
}

module.exports = DeviceCache;