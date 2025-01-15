const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const axios = require('axios');

// Database paths
const DB_PATH = path.join(__dirname, '../src/database');

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
  ouiVendor: new sqlite3.Database(path.join(DB_PATH, 'oui-vendor.sqlite'))
};

async function initializeDatabases() {
  const promises = [];

  // Add configs table to openwalla database with all default values
  promises.push(new Promise((resolve, reject) => {
    databases.openwalla.run(`
      CREATE TABLE IF NOT EXISTS configs (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    `, [], (err) => {
      if (err) reject(err);
      else {
        // Insert default config values if they don't exist
        const defaultConfigs = Object.entries(require('./utils/config').getEnvConfig());
        
        const stmt = databases.openwalla.prepare(
          'INSERT OR IGNORE INTO configs (key, value) VALUES (?, ?)'
        );

        defaultConfigs.forEach(([key, value]) => {
          stmt.run(key, String(value), (err) => {
            if (err) console.error(`Error inserting default config ${key}:`, err);
          });
        });

        stmt.finalize((err) => {
          if (err) reject(err);
          else resolve();
        });
      }
    });
  }));

  // Notifications database
  promises.push(new Promise((resolve, reject) => {
    databases.notifications.run(`
      CREATE TABLE IF NOT EXISTS notifications (
        uuid TEXT PRIMARY KEY,
        sev TEXT,
        type TEXT,
        msg TEXT,
        detect_time INTEGER,
        action TEXT
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  // Client table in devices database
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
    if (err) console.error('Error creating nlbw table:', err);
    else console.log('NLBW table initialized');
  });

  // Flow database
  databases.flows.run(`
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
    if (err) console.error('Error creating flow table:', err);
    else console.log('Flow table initialized');
  });

  // Vnstat hourly table
  databases.vnstat.run(`
    CREATE TABLE IF NOT EXISTS hourly (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER,
      month INTEGER,
      day INTEGER,
      hour INTEGER,
      rx INTEGER,
      tx INTEGER,
      timestamp INTEGER,
      interface_name TEXT,
      UNIQUE(year, month, day, hour, interface_name)
    )
  `, [], (err) => {
    if (err) console.error('Error creating vnstat hourly table:', err);
    else console.log('Vnstat hourly table initialized');
  });

  // Vnstat monthly table
  databases.vnstat.run(`
    CREATE TABLE IF NOT EXISTS monthly (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER,
      month INTEGER,
      rx INTEGER,
      tx INTEGER,
      timestamp INTEGER,
      interface_name TEXT,
      UNIQUE(year, month, interface_name)
    )
  `, [], (err) => {
    if (err) console.error('Error creating vnstat monthly table:', err);
    else console.log('Vnstat monthly table initialized');
  });

  // Vnstat daily table
  databases.vnstat.run(`
    CREATE TABLE IF NOT EXISTS daily (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER,
      month INTEGER,
      day INTEGER,
      rx INTEGER,
      tx INTEGER,
      interface_name TEXT,
      UNIQUE(year, month, day, interface_name)
    )
  `, [], (err) => {
    if (err) console.error('Error creating vnstat daily table:', err);
    else console.log('Vnstat daily table initialized');
  });

  // OUI Vendor database
  databases.ouiVendor.run(`
    CREATE TABLE IF NOT EXISTS oui_vendors (
      oui TEXT PRIMARY KEY,
      vendor TEXT NOT NULL
    )
  `, [], async (err) => {
    if (err) {
      console.error('Error creating oui_vendors table:', err);
    } else {
      console.log('OUI vendors table initialized');
      
      // Check if table is empty
      databases.ouiVendor.get('SELECT COUNT(*) as count FROM oui_vendors', [], async (err, row) => {
        if (err) {
          console.error('Error checking oui_vendors count:', err);
        } else if (row.count === 0) {
          console.log('Populating OUI vendors table...');
          try {
            const response = await axios.get('https://raw.githubusercontent.com/benisai/Openwalla/main/mac-address-oui.json');
            const vendors = response.data;
            
            const stmt = databases.ouiVendor.prepare('INSERT OR REPLACE INTO oui_vendors (oui, vendor) VALUES (?, ?)');
            Object.entries(vendors).forEach(([vendorName, ouis]) => {
              const ouiArray = Array.isArray(ouis) ? ouis : [ouis];
              ouiArray.forEach(oui => {
                stmt.run(oui.toLowerCase(), vendorName);
              });
            });
            stmt.finalize();
            
            console.log('OUI vendors table populated successfully');
          } catch (error) {
            console.error('Error populating OUI vendors:', error);
          }
        }
      });
    }
  });

  // Ping stats database with enhanced schema
  promises.push(new Promise((resolve, reject) => {
    databases.pingStats.run(`
      CREATE TABLE IF NOT EXISTS pingstats (
        uuid TEXT PRIMARY KEY,
        ip TEXT,
        ms REAL,
        max_latency REAL,
        median_latency REAL,
        packetloss REAL,
        date TEXT,
        time TEXT,
        timestamp INTEGER,
        target_ip TEXT,
        latency REAL,
        packet_loss REAL,
        status TEXT,
        error_message TEXT
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  // Add device types table
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

  try {
    await Promise.all(promises);
    console.log('All database tables initialized successfully');
  } catch (error) {
    console.error('Error initializing database tables:', error);
    throw error;
  }
}

module.exports = {
  databases,
  initializeDatabases
};
