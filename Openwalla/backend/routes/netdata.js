const express = require('express');
const router = express.Router();
const NetdataService = require('../services/NetdataService');
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

// Create Netdata service instance with config
let netdataService = null;

// Initialize Netdata service
const initializeNetdataService = async (req, res, next) => {
  try {
    const config = await getConfig();
    
    // Always create a fresh instance to ensure latest config
    netdataService = new NetdataService(config);
    
    next();
  } catch (error) {
    console.error('Failed to initialize Netdata service:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to initialize Netdata service'
    });
  }
};

// Use the middleware for all routes
router.use(initializeNetdataService);

// Get system metrics
router.get('/metrics', async (req, res) => {
  try {
    const metrics = await netdataService.fetchSystemMetrics();
    res.json({
      success: true,
      data: metrics
    });
  } catch (error) {
    console.error('Error fetching system metrics:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get system load
router.get('/load', async (req, res) => {
  try {
    const load = await netdataService.fetchSystemLoad();
    res.json({
      success: true,
      data: load
    });
  } catch (error) {
    console.error('Error fetching system load:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
