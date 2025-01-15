const axios = require('axios');
const VnstatParser = require('./vnstat/VnstatParser');
const VnstatDatabaseManager = require('./vnstat/VnstatDatabaseManager');
const { databases } = require('../database');

class VnstatService {
  constructor() {
    this.getVnstatUrl();
  }

  async getVnstatUrl() {
    return new Promise((resolve, reject) => {
      databases.openwalla.get('SELECT value FROM configs WHERE key = ?', ['vnstat_url'], (err, row) => {
        if (err) {
          console.error('Error getting vnstat_url from config:', err);
          this.url = 'http://192.168.1.1/vnstat.txt'; // Default fallback
          resolve(this.url);
        } else {
          this.url = row ? row.value : 'http://192.168.1.1/vnstat.txt';
          resolve(this.url);
        }
      });
    });
  }

  async fetchVnstatData() {
    try {
      await this.getVnstatUrl(); // Ensure we have the latest URL
      const response = await axios.get(this.url);
      console.log('Vnstat data fetched successfully from:', this.url);
      return response.data;
    } catch (error) {
      console.error('Error fetching vnstat data:', error);
      return null;
    }
  }

  async updateData() {
    try {
      console.log('Starting vnstat data update');
      const rawData = await this.fetchVnstatData();
      if (!rawData) return;

      const data = VnstatParser.parseVnstatText(rawData);
      
      // Process monthly data
      for (const month of data.monthly) {
        try {
          await VnstatDatabaseManager.saveMonthlyData(month);
        } catch (error) {
          console.error('Error saving monthly data:', error);
        }
      }

      // Process daily data
      for (const day of data.daily) {
        try {
          await VnstatDatabaseManager.saveDailyData(day);
        } catch (error) {
          console.error('Error saving daily data:', error);
        }
      }

      // Process hourly data
      for (const hour of data.hourly) {
        try {
          await VnstatDatabaseManager.saveHourlyData(hour);
        } catch (error) {
          console.error('Error saving hourly data:', error);
        }
      }
      
      console.log('Vnstat data updated successfully');
    } catch (error) {
      console.error('Error updating vnstat data:', error);
    }
  }

  startHourlyUpdates() {
    console.log('Starting vnstat hourly updates service');
    // Initial update
    this.updateData();
    
    // Schedule hourly updates
    setInterval(() => {
      this.updateData();
    }, 60 * 60 * 1000); // Run every hour
  }
}

module.exports = VnstatService;