const express = require('express');
const { databases, initializeDatabases } = require('./database');
const ServicesManager = require('./services/ServicesManager');
const { getEnvConfig } = require('./utils/config');

// Import routes
const flowsRouter = require('./routes/flows');
const devicesRouter = require('./routes/devices');
const notificationsRouter = require('./routes/notifications');
const pingStatsRouter = require('./routes/pingStats');
const adblockRouter = require('./routes/adblock');
const configRouter = require('./routes/config');
const vnstatRouter = require('./routes/vnstat');

const app = express();
app.use(express.json());

// Get config from environment variables
const DEFAULT_CONFIG = getEnvConfig();

let servicesManager;

// Initialize databases before starting services
async function startServer() {
  try {
    // First initialize the databases with default configs
    await initializeDatabases();
    console.log('Databases initialized successfully');
    
    // Get initial config from database
    const config = await new Promise((resolve, reject) => {
      databases.openwalla.all('SELECT key, value FROM configs', [], (err, rows) => {
        if (err) {
          console.error('Error reading initial config from database:', err);
          reject(err);
        } else {
          const configObj = { ...DEFAULT_CONFIG };
          rows.forEach(row => {
            configObj[row.key] = row.value;
          });
          resolve(configObj);
        }
      });
    });

    // Initialize services manager with config from database
    servicesManager = new ServicesManager(config);
    await servicesManager.startAll();

    // Set up routes
    app.use('/api/flows', flowsRouter);
    app.use('/api/devices', devicesRouter);
    app.use('/api/notifications', notificationsRouter);
    app.use('/api/ping-stats', pingStatsRouter);
    app.use('/api/adblock', adblockRouter);
    app.use('/api/config', configRouter);
    app.use('/api/vnstat', vnstatRouter);

    // Start Express server
    const PORT = process.env.PORT || 3000;
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

// Handle process termination
process.on('SIGINT', () => {
  console.log('Closing database connections...');
  Object.values(databases).forEach(db => db.close());
  if (servicesManager) {
    servicesManager.stopAll();
  }
  process.exit();
});