// backend/server.js

const express = require('express');
const path = require('path');
const fs = require('fs');
const { databases, initializeDatabases } = require('./database/database');
const ServicesManager = require('./services/ServicesManager');
// 🚀 NEW IMPORT: Speedtest Scheduler Service
const { startScheduler } = require('./services/speedtest/speedtestScheduler');

const app = express();
app.use(express.json());

let servicesManager;

// Initialize databases before starting services
async function startServer() {
    try {
        // Set database directory
        const databaseDir = path.join(__dirname, '../databases');
        
        // First initialize the databases with default configs
        await initializeDatabases();
        console.log('Databases initialized successfully');
        
        // Import and register API routes FIRST (before services start)
        const authRoutes = require('./routes/auth');
        const deviceRoutes = require('./routes/devices');
        const flowRoutes = require('./routes/flows');
        const vnstatRoutes = require('./routes/vnstat');
        const notificationRoutes = require('./routes/notifications');
        const ruleRoutes = require('./routes/rules');
        const configRoutes = require('./routes/config');
        const applicationUsageRoutes = require('./routes/applicationUsage');
        const pingStatsRoutes = require('./routes/pingStats');
        const openwrtRoutes = require('./routes/openwrt');
        const pingRestartRoutes = require('./routes/pingRestart');
        const serviceRestartRoutes = require('./routes/serviceRestart');
        const speedtestRoutes = require('./routes/speedtest'); 

        app.use('/api/auth', authRoutes);
        app.use('/api/devices', deviceRoutes);
        app.use('/api/flows', flowRoutes);
        app.use('/api/vnstat', vnstatRoutes);
        app.use('/api/notifications', notificationRoutes);
        app.use('/api/rules', ruleRoutes);
        app.use('/api/config', configRoutes);
        app.use('/api/application-usage', applicationUsageRoutes);
        app.use('/api/ping-stats', pingStatsRoutes);
        app.use('/api/openwrt', openwrtRoutes);
        app.use('/api/ping/restart', pingRestartRoutes);
        app.use('/api/service/restart', serviceRestartRoutes);
        app.use('/api/speedtest', speedtestRoutes); 

        // Start Express server BEFORE initializing services
        const PORT = process.env.PORT || 3000;
        app.listen(PORT, () => {
            console.log(`Server running on port ${PORT}`);
            console.log('Auth routes are ready - login is now available');
        });

        // 🚀 NEW EXECUTION: Start the nightly speed test scheduler
        startScheduler();
        
        // Initialize services in the background after server is ready
        console.log('Starting background services...');
        
        // Get config from database for services
        const config = await new Promise((resolve, reject) => {
            databases.configs.all('SELECT key, value FROM configs', [], (err, rows) => {
                if (err) {
                    console.error('Error reading config from database:', err);
                    reject(err);
                } else {
                    const configObj = {};
                    rows.forEach(row => {
                        configObj[row.key] = row.value;
                    });
                    configObj.database_dir = databaseDir;
                    resolve(configObj);
                }
            });
        });

        // Initialize services manager with config and start services
        servicesManager = new ServicesManager(config);
        
        // Set services manager for restart routes
        pingRestartRoutes.setServicesManager(servicesManager);
        serviceRestartRoutes.setServicesManager(servicesManager);
        
        // Start all services in background (non-blocking)
        servicesManager.startAll().then(() => {
            console.log('All background services initialized');
        }).catch(err => {
            console.error('Error starting services:', err);
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
