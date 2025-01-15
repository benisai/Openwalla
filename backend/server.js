const express = require('express');
const path = require('path');
const fs = require('fs');
const flowsRouter = require('./routes/flows');
const devicesRouter = require('./routes/devices');
const notificationsRouter = require('./routes/notifications');
const pingStatsRouter = require('./routes/pingStats');
const { databases, initializeDatabases } = require('./database');
const ServicesManager = require('./services/ServicesManager');
const { getEnvConfig } = require('./utils/config');

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

app.get('/api/config', (req, res) => {
  databases.openwalla.all('SELECT key, value FROM configs', [], (err, rows) => {
    if (err) {
      console.error('Error reading config from database:', err);
      res.status(500).json({ error: 'Failed to read config' });
    } else {
      const config = { ...DEFAULT_CONFIG };
      rows.forEach(row => {
        config[row.key] = row.value;
      });
      res.json(config);
    }
  });
});

app.post('/api/config', (req, res) => {
  const updates = req.body;
  const stmt = databases.openwalla.prepare('INSERT OR REPLACE INTO configs (key, value) VALUES (?, ?)');
  
  try {
    Object.entries(updates).forEach(([key, value]) => {
      stmt.run(key, value);
    });
    
    stmt.finalize(async (err) => {
      if (err) {
        console.error('Error saving config to database:', err);
        res.status(500).json({ error: 'Failed to save config' });
      } else {
        // Get updated config
        databases.openwalla.all('SELECT key, value FROM configs', [], async (err, rows) => {
          if (err) {
            res.status(500).json({ error: 'Failed to read updated config' });
          } else {
            const newConfig = { ...DEFAULT_CONFIG };
            rows.forEach(row => {
              newConfig[row.key] = row.value;
            });
            
            // Update services with new config
            if (servicesManager) {
              await servicesManager.updateConfig(newConfig);
            }
            
            res.json(newConfig);
          }
        });
      }
    });
  } catch (error) {
    console.error('Error processing config updates:', error);
    res.status(500).json({ error: 'Failed to save config' });
  }
});

// Vnstat routes
app.get('/api/vnstat/daily', (req, res) => {
  const today = new Date();
  const firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
  const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
  
  const sql = `
    SELECT year, month, day, rx, tx, interface_name 
    FROM daily 
    WHERE year = ? AND month = ?
    ORDER BY day ASC
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat daily data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

app.get('/api/vnstat/monthly', (req, res) => {
  const today = new Date();
  const sql = `
    SELECT year, month, rx, tx, interface_name
    FROM monthly 
    WHERE year = ? AND month = ?
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat monthly data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows);
    }
  });
});

// Vnstat hourly route
app.get('/api/vnstat/hourly', (req, res) => {
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  
  const sql = `
    WITH unique_hours AS (
      SELECT DISTINCT year, month, day, hour, rx, tx, interface_name, timestamp,
             ROW_NUMBER() OVER (PARTITION BY year, month, day, hour ORDER BY timestamp DESC) as rn
      FROM hourly 
      WHERE (year = ? AND month = ? AND day = ?) OR 
            (year = ? AND month = ? AND day = ?)
    )
    SELECT year, month, day, hour, rx, tx, interface_name, timestamp
    FROM unique_hours 
    WHERE rn = 1
    ORDER BY timestamp DESC 
    LIMIT 12
  `;
  
  databases.vnstat.all(sql, [
    today.getFullYear(),
    today.getMonth() + 1,
    today.getDate(),
    yesterday.getFullYear(),
    yesterday.getMonth() + 1,
    yesterday.getDate()
  ], (err, rows) => {
    if (err) {
      console.error('Error fetching vnstat hourly data:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json(rows.reverse()); // Reverse to get chronological order
    }
  });
});

// Start Express server

// Add this new route before the app.listen call

// Add this new route before the app.listen call

// Add this new route before the app.listen call
app.post('/api/netify/restart', async (req, res) => {
  try {
    if (servicesManager) {
      if (servicesManager.services.netify) {
        await servicesManager.services.netify.disconnect();
        await servicesManager.startNetifyService();
        res.json({ message: 'Netify service restarted successfully' });
      } else {
        await servicesManager.startNetifyService();
        res.json({ message: 'Netify service started successfully' });
      }
    } else {
      throw new Error('Services manager not initialized');
    }
  } catch (error) {
    console.error('Error restarting Netify service:', error);
    res.status(500).json({ error: 'Failed to restart Netify service' });
  }
});

app.post('/api/ping/restart', async (req, res) => {
  try {
    if (servicesManager) {
      await servicesManager.services.internetMonitor?.stop();
      await servicesManager.services.internetMonitor?.start();
      res.json({ message: 'Ping service restarted successfully' });
    } else {
      throw new Error('Services manager not initialized');
    }
  } catch (error) {
    console.error('Error restarting ping service:', error);
    res.status(500).json({ error: 'Failed to restart ping service' });
  }
});

app.get('/api/vendor/:mac', (req, res) => {
  const mac = req.params.mac.toLowerCase();
  const oui = mac.split(':').slice(0, 3).join(':');
  
  databases.ouiVendor.get('SELECT vendor FROM oui_vendors WHERE oui = ?', [oui], (err, row) => {
    if (err) {
      console.error('Error fetching vendor:', err);
      res.status(500).json({ error: 'Database error' });
    } else {
      res.json({ vendor: row ? row.vendor : 'Unknown' });
    }
  });
});

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
