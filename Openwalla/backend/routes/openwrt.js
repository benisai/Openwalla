
/**
 * OpenWrt API routes
 */
const express = require('express');
const router = express.Router();
const OpenWrtService = require('../services/OpenWrtService');
const { databases } = require('../database/database');

// Get config from database
const getConfig = async () => {
  return new Promise((resolve, reject) => {
    databases.configs.all('SELECT key, value FROM configs', [], (err, rows) => {
      if (err) {
        reject(err);
      } else {
        const config = {};
        rows.forEach(row => {
          config[row.key] = row.value;
        });
        resolve(config);
      }
    });
  });
};

// Create OpenWrt service instance with config
let openWrtService = null;

// Initialize OpenWrt service
const initializeOpenWrtService = async (req, res, next) => {
  try {
    const config = await getConfig();
    
    // Always create a fresh instance to ensure latest config
    openWrtService = new OpenWrtService(config);
    
    next();
  } catch (error) {
    console.error('Failed to initialize OpenWrt service:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to initialize OpenWrt service'
    });
  }
};

// Use the middleware for all routes
router.use(initializeOpenWrtService);

// Test connection to OpenWrt
router.get('/test-connection', async (req, res) => {
  try {
    console.log('Testing OpenWrt connection...');
    const result = await openWrtService.testConnection();
    
    console.log('OpenWrt test result:', result);
    res.json(result);
  } catch (error) {
    console.error('OpenWrt test connection error:', error);
    res.status(500).json({
      success: false,
      error: error.message,
      details: {
        reachable: false,
        authenticated: false
      }
    });
  }
});

// Get router status
router.get('/status', async (req, res) => {
  try {
    const status = await openWrtService.getRouterStatus();
    res.json({
      success: true,
      data: status
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get system info
router.get('/system-info', async (req, res) => {
  try {
    const systemInfo = await openWrtService.getSystemInfo();
    res.json({
      success: true,
      data: systemInfo
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get network interfaces
router.get('/network', async (req, res) => {
  try {
    const networkInterfaces = await openWrtService.getNetworkInterfaces();
    res.json({
      success: true,
      data: networkInterfaces
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get wireless config
router.get('/wireless', async (req, res) => {
  try {
    const wirelessConfig = await openWrtService.getWirelessConfig();
    res.json({
      success: true,
      data: wirelessConfig
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
