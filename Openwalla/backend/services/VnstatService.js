const axios = require('axios');
const VnstatParser = require('./vnstat/VnstatParser');
const VnstatDatabaseManager = require('./vnstat/VnstatDatabaseManager');
const { databases } = require('../database/database');

class VnstatService {
  constructor(config) {
    this.url = `http://${config.router_ip || '192.168.1.1'}/vnstat.txt`;
  }

  async fetchVnstatData() {
    try {
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
      //console.log('Starting vnstat data update');
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
    //console.log('Starting vnstat hourly updates service');
    // Initial update
    this.updateData();
    
    // Schedule hourly updates
    this.interval = setInterval(() => {
      this.updateData();
    }, 60 * 60 * 1000); // Run every hour
  }

  stop() {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
      console.log('Vnstat service stopped');
    }
  }
}

module.exports = VnstatService;
