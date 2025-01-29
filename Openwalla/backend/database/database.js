/**
 * Database Configuration and Initialization
 * 
 * This module manages:
 * - Database connections for different data stores
 * - Schema initialization
 * - Database directory creation
 * - Error handling for database operations
 * 
 * The databases object contains connections to:
 * - configs: System configuration
 * - openwalla: Core application data
 * - openwrt: Router-specific data
 * - flows: Network traffic flows
 * - notifications: System notifications
 * - pingStats: Network performance data
 * - devices: Connected device information
 * - vnstat: Network statistics
 * - ouiVendor: Device manufacturer data
 */
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const { getEnvConfig } = require('../configs/config');
// Get the environment configuration
const envConfig = getEnvConfig();
// Database paths
const DB_PATH = path.join(__dirname, '../../databases');

// Import schema initialization functions
const initializeConfigs = require('./config');
const initializeNotifications = require('./schemas/notificationSchema');
const initializeDevices = require('./schemas/deviceSchema');
const initializeFlows = require('./schemas/flowSchema');
const initializeVnstat = require('./schemas/vnstatSchema');
const initializeOuiVendor = require('./schemas/ouiVendorSchema');
const initializePingStats = require('./schemas/pingStatsSchema');
const initializeRxTx = require('./schemas/rxTxSchema');



// Ensure database directory exists
if (!fs.existsSync(DB_PATH)) {
  console.log('Creating database directory:', DB_PATH);
  fs.mkdirSync(DB_PATH, { recursive: true });
}

// Configure databases
const databases = {
  configs: new sqlite3.Database(path.join(DB_PATH, 'configs.sqlite')),  
  openwalla: new sqlite3.Database(path.join(DB_PATH, 'openwalla.sqlite')),
  openwrt: new sqlite3.Database(path.join(DB_PATH, 'openwrt.sqlite')),
  flows: new sqlite3.Database(path.join(DB_PATH, 'flows.sqlite')),
  blockedFlows: new sqlite3.Database(path.join(DB_PATH, 'blockedflows.sqlite')),
  notifications: new sqlite3.Database(path.join(DB_PATH, 'notifications.sqlite')),
  hourlyWanUsage: new sqlite3.Database(path.join(DB_PATH, 'hourlywanusage.sqlite')),
  pingStats: new sqlite3.Database(path.join(DB_PATH, 'pingstats.sqlite')),
  devices: new sqlite3.Database(path.join(DB_PATH, 'devices.sqlite')),
  vnstat: new sqlite3.Database(path.join(DB_PATH, 'vnstat.sqlite')),
  ouiVendor: new sqlite3.Database(path.join(DB_PATH, 'oui-vendor.sqlite')),
};

async function initializeDatabases() {
  try {
    // Initialize tables in their respective databases
    await initializeConfigs(databases.configs, envConfig);    
    await initializeNotifications(databases.notifications);
    await initializeDevices(databases.devices);
    await initializeFlows(databases.flows);
    await initializeVnstat(databases.vnstat);
    await initializeOuiVendor(databases.ouiVendor, envConfig);
    await initializePingStats(databases.pingStats);
    await initializeRxTx(databases.devices);

    console.log('All database tables initialized successfully');
  } catch (error) {
    console.error('Error initializing database tables:', error);
    throw error;
  }
}

module.exports = {
  databases,
  initializeDatabases,
};

