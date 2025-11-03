
import sqlite3 from 'sqlite3';
import { DATABASE_CONFIG } from '../src/config/database';

// Enable verbose mode for debugging
sqlite3.verbose();

// Create database connections
const openwallaDb = new sqlite3.Database(DATABASE_CONFIG.OPENWALLA_DB);
const openwrtDb = new sqlite3.Database(DATABASE_CONFIG.OPENWRT_DB);
const flowsDb = new sqlite3.Database(DATABASE_CONFIG.FLOWS_DB);
const configsDb = new sqlite3.Database(DATABASE_CONFIG.CONFIGS_DB);
const notificationsDb = new sqlite3.Database(DATABASE_CONFIG.NOTIFICATIONS_DB);
const hourlyWanUsageDb = new sqlite3.Database(DATABASE_CONFIG.HOURLY_WAN_USAGE_DB);
const pingStatsDb = new sqlite3.Database(DATABASE_CONFIG.PING_STATS_DB);

// Initialize tables for each database
async function initializeDatabases(): Promise<void> {
  // Drop and recreate flow table to ensure schema is up to date
  await new Promise<void>((resolve, reject) => {
    flowsDb.run('DROP TABLE IF EXISTS flow', (err) => {
      if (err) {
        console.error('Error dropping flow table:', err);
        reject(err);
      } else {
        console.log('Flow table dropped successfully');
        resolve();
      }
    });
  });

  // Create stats_purge table
  await new Promise<void>((resolve, reject) => {
    flowsDb.run(`
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
    `, (err) => {
      if (err) {
        console.error('Error creating stats_purge table:', err);
        reject(err);
      } else {
        console.log('Stats_purge table created successfully');
        resolve();
      }
    });
  });

  // Create flow table
  await new Promise<void>((resolve, reject) => {
    flowsDb.run(`
      CREATE TABLE flow (
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
    `, (err) => {
      if (err) {
        console.error('Error creating flow table:', err);
        reject(err);
      } else {
        console.log('Flow table created successfully');
        resolve();
      }
    });
  });

  // Notifications database
  await new Promise<void>((resolve, reject) => {
    notificationsDb.run(`
      CREATE TABLE IF NOT EXISTS notifications (
        uuid TEXT PRIMARY KEY,
        sev TEXT,
        type TEXT,
        msg TEXT,
        detect_time INTEGER,
        action TEXT
      )
    `, (err) => {
      if (err) {
        console.error('Error creating notifications table:', err);
        reject(err);
      } else {
        resolve();
      }
    });
  });

  // Devices database (in OpenWRT DB)
  await new Promise<void>((resolve, reject) => {
    openwrtDb.run(`
      CREATE TABLE IF NOT EXISTS devices (
        uuid TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        mac TEXT,
        ip TEXT,
        netname TEXT,
        manufacturer TEXT,
        status TEXT,
        portscount INTEGER
      )
    `, (err) => {
      if (err) {
        console.error('Error creating devices table:', err);
        reject(err);
      } else {
        resolve();
      }
    });
  });

  // Hourly WAN usage database
  await new Promise<void>((resolve, reject) => {
    hourlyWanUsageDb.run(`
      CREATE TABLE IF NOT EXISTS hourlywanusage (
        uuid TEXT PRIMARY KEY,
        interface TEXT,
        name TEXT,
        hour INTEGER,
        download REAL,
        upload REAL
      )
    `, (err) => {
      if (err) {
        console.error('Error creating hourlywanusage table:', err);
        reject(err);
      } else {
        resolve();
      }
    });
  });

  // Ping stats database
  await new Promise<void>((resolve, reject) => {
    pingStatsDb.run(`
      CREATE TABLE IF NOT EXISTS pingstats (
        uuid TEXT PRIMARY KEY,
        ip TEXT,
        ms INTEGER,
        max_latency REAL,
        median_latency REAL,
        packetloss REAL,
        date TEXT,
        time TEXT
      )
    `, (err) => {
      if (err) {
        console.error('Error creating pingstats table:', err);
        reject(err);
      } else {
        resolve();
      }
    });
  });

  console.log('All database tables initialized successfully');
}

// Initialize all databases
initializeDatabases().catch(console.error);

// Export database connections
export const databases = {
  openwalla: openwallaDb,
  openwrt: openwrtDb,
  flows: flowsDb,
  configs: configsDb,
  notifications: notificationsDb,
  hourlyWanUsage: hourlyWanUsageDb,
  pingStats: pingStatsDb,
};
