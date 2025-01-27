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
function initializeDatabases() {
  // Notifications database
  notificationsDb.run(`
    CREATE TABLE IF NOT EXISTS notifications (
      uuid TEXT PRIMARY KEY,
      sev TEXT,
      type TEXT,
      msg TEXT,
      detect_time INTEGER,
      action TEXT
    )
  `);

  // Devices database (in OpenWRT DB)
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
  `);

  // Hourly WAN usage database
  hourlyWanUsageDb.run(`
    CREATE TABLE IF NOT EXISTS hourlywanusage (
      uuid TEXT PRIMARY KEY,
      interface TEXT,
      name TEXT,
      hour INTEGER,
      download REAL,
      upload REAL
    )
  `);

  // Ping stats database
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
  `);

  // Flow database with updated schema
  flowsDb.run(`
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
  `);

  console.log('Database tables initialized');
}

// Initialize all databases
initializeDatabases();

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
