
const { databases } = require('../../database/database');

class NetifyDeviceCache {
  constructor() {
    this.deviceCache = new Map();
    this.CACHE_REFRESH_INTERVAL = 5 * 60 * 1000; // 5 minutes
  }

  async loadDeviceCache() {
    const sql = `
      SELECT mac, hostname, ip
      FROM clients
    `;
    
    return new Promise((resolve, reject) => {
      databases.devices.all(sql, [], (err, rows) => {
        if (err) {
          console.error('[NetifyDeviceCache] Error loading device cache:', err);
          reject(err);
        } else {
          this.deviceCache.clear();
          rows.forEach(row => {
            this.deviceCache.set(row.mac.toLowerCase(), {
              hostname: row.hostname,
              ip: row.ip
            });
          });
          resolve();
        }
      });
    });
  }

  startCacheRefresh() {
    this.loadDeviceCache();
    setInterval(() => {
      this.loadDeviceCache();
    }, this.CACHE_REFRESH_INTERVAL);
  }

  getDeviceInfo(mac) {
    const cachedDevice = this.deviceCache.get(mac.toLowerCase());
    if (cachedDevice) {
      return Promise.resolve(cachedDevice);
    }
    
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT hostname, ip
        FROM clients
        WHERE mac = ?
      `;
      
      databases.devices.get(sql, [mac.toLowerCase()], (err, row) => {
        if (err) {
          console.error('[NetifyDeviceCache] Error getting device info:', err);
          reject(err);
        } else {
          const deviceInfo = row || { hostname: '', ip: '' };
          this.deviceCache.set(mac.toLowerCase(), deviceInfo);
          resolve(deviceInfo);
        }
      });
    });
  }
}

module.exports = NetifyDeviceCache;
