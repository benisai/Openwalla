
const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

let servicesManagerInstance = null;

// Allow setting the services manager instance
router.setServicesManager = (manager) => {
  servicesManagerInstance = manager;
};

// Restart ping service with updated config
router.post('/', async (req, res) => {
  try {
    if (!servicesManagerInstance) {
      return res.status(500).json({ error: 'Services manager not available' });
    }

    // Get updated config from database
    const configRows = await new Promise((resolve, reject) => {
      databases.configs.all('SELECT key, value FROM configs', [], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });

    const newConfig = {};
    configRows.forEach(row => {
      newConfig[row.key] = row.value;
    });

    // Stop current internet monitor service
    if (servicesManagerInstance.services.internetMonitor) {
      servicesManagerInstance.services.internetMonitor.stop();
    }

    // Update config and restart internet monitor
    servicesManagerInstance.config = { ...servicesManagerInstance.config, ...newConfig };
    await servicesManagerInstance.startInternetMonitor();

    console.log('Internet monitor service restarted with new config:', {
      ping_address: newConfig.ping_address,
      latency_threshold: newConfig.latency_threshold
    });

    res.json({ success: true, message: 'Ping service restarted successfully' });
  } catch (error) {
    console.error('Error restarting ping service:', error);
    res.status(500).json({ error: 'Failed to restart ping service' });
  }
});

module.exports = router;
