
const express = require('express');
const router = express.Router();
const { databases } = require('../database/database');

let servicesManagerInstance = null;

// Allow setting the services manager instance
router.setServicesManager = (manager) => {
  servicesManagerInstance = manager;
};

// Restart any service with updated config
router.post('/:serviceName', async (req, res) => {
  try {
    const { serviceName } = req.params;
    
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

    console.log(`[${serviceName}] Restarting with updated config:`, newConfig);

    // Update the services manager config - completely replace it
    servicesManagerInstance.config = newConfig;

    // Restart the specific service
    switch(serviceName.toLowerCase()) {
      case 'internetmonitor':
      case 'internet-monitor':
        if (servicesManagerInstance.services.internetMonitor) {
          servicesManagerInstance.services.internetMonitor.stop();
        }
        await servicesManagerInstance.startInternetMonitor();
        console.log('Internet monitor service restarted with new config');
        break;

      case 'netify':
        if (servicesManagerInstance.services.netify) {
          servicesManagerInstance.services.netify.stop();
        }
        await servicesManagerInstance.startNetifyService();
        console.log('Netify service restarted with new config');
        break;

      case 'vnstat':
        if (servicesManagerInstance.services.vnstat) {
          servicesManagerInstance.services.vnstat.stop();
        }
        await servicesManagerInstance.startVnstatService();
        console.log('Vnstat service restarted with new config');
        break;

      case 'devices':
        if (servicesManagerInstance.services.devices) {
          servicesManagerInstance.services.devices.stop();
        }
        await servicesManagerInstance.startDeviceService();
        console.log('Device service restarted with new config');
        break;

      case 'openwrt':
        await servicesManagerInstance.startOpenWrtService();
        console.log('OpenWrt service restarted with new config');
        break;

      case 'netdata':
        // Netdata is an external service, we just acknowledge the restart request
        console.log('Netdata restart acknowledged (external service)');
        break;

      default:
        return res.status(400).json({ error: 'Unknown service name' });
    }

    res.json({ success: true, message: `${serviceName} service restarted successfully` });
  } catch (error) {
    console.error(`Error restarting service:`, error);
    res.status(500).json({ error: `Failed to restart service: ${error.message}` });
  }
});

module.exports = router;
