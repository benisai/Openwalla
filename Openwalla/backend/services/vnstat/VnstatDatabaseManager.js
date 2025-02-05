const { databases } = require('../../database/database');

class VnstatDatabaseManager {
  static async saveHourlyData(hourData) {
    return new Promise((resolve, reject) => {
      // Calculate timestamp from year, month, day, hour
      const timestamp = new Date(
        hourData.year,
        hourData.month - 1, // JavaScript months are 0-based
        hourData.day,
        hourData.hour
      ).getTime() / 1000; // Convert to Unix timestamp (seconds)

      databases.vnstat.run(`
        INSERT OR REPLACE INTO hourly 
        (year, month, day, hour, rx, tx, interface_name, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        hourData.year,
        hourData.month,
        hourData.day,
        hourData.hour,
        hourData.rx,
        hourData.tx,
        hourData.interface_name,
        timestamp
      ], (err) => {
        if (err) {
          console.error('Error saving hourly data:', err);
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  static async saveDailyData(dayData) {
    return new Promise((resolve, reject) => {
      databases.vnstat.run(`
        INSERT OR REPLACE INTO daily 
        (year, month, day, rx, tx, interface_name)
        VALUES (?, ?, ?, ?, ?, ?)
      `, [
        dayData.year,
        dayData.month,
        dayData.day,
        dayData.rx,
        dayData.tx,
        dayData.interface_name
      ], (err) => {
        if (err) {
          console.error('Error saving daily data:', err);
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  static async saveMonthlyData(monthData) {
    return new Promise((resolve, reject) => {
      databases.vnstat.run(`
        INSERT OR REPLACE INTO monthly 
        (year, month, rx, tx, interface_name)
        VALUES (?, ?, ?, ?, ?)
      `, [
        monthData.year,
        monthData.month,
        monthData.rx,
        monthData.tx,
        monthData.interface_name
      ], (err) => {
        if (err) {
          console.error('Error saving monthly data:', err);
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }
}

module.exports = VnstatDatabaseManager;