const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

// Database paths
const DB_PATH = path.join(__dirname, '../../src/database');

// Ensure database directory exists
if (!fs.existsSync(DB_PATH)) {
  console.log('Creating database directory:', DB_PATH);
  fs.mkdirSync(DB_PATH, { recursive: true });
}

const databases = {
  openwalla: new sqlite3.Database(path.join(DB_PATH, 'openwalla.sqlite')),
  openwrt: new sqlite3.Database(path.join(DB_PATH, 'openwrt.sqlite')),
  flows: new sqlite3.Database(path.join(DB_PATH, 'flows.sqlite')),
  blockedFlows: new sqlite3.Database(path.join(DB_PATH, 'blockedflows.sqlite')),
  configs: new sqlite3.Database(path.join(DB_PATH, 'configs.sqlite')),
  notifications: new sqlite3.Database(path.join(DB_PATH, 'notifications.sqlite')),
  hourlyWanUsage: new sqlite3.Database(path.join(DB_PATH, 'hourlywanusage.sqlite')),
  pingStats: new sqlite3.Database(path.join(DB_PATH, 'pingstats.sqlite')),
  devices: new sqlite3.Database(path.join(DB_PATH, 'devices.sqlite')),
  vnstat: new sqlite3.Database(path.join(DB_PATH, 'vnstat.sqlite')),
  ouiVendor: new sqlite3.Database(path.join(DB_PATH, 'oui-vendor.sqlite')),
  adblock: new sqlite3.Database(path.join(DB_PATH, 'adblock.sqlite'))
};

module.exports = databases;