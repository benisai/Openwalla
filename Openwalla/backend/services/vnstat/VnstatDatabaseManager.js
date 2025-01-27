const { databases } = require('../../database/database');

class VnstatDatabaseManager {
  static async saveHourlyData(hourData) {
    return new Promise((resolve, reject) => {
      //console.log('Saving hourly data:', hourData);
      databases.vnstat.run(`
        INSERT OR REPLACE INTO hourly 
        (year, month, day, hour, rx, tx, timestamp, interface_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        hourData.year,
        hourData.month,
        hourData.day,
        hourData.hour,
        hourData.rx,
        hourData.tx,
        hourData.timestamp,
        hourData.interface_name
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
        (year, month, rx, tx, timestamp, interface_name)
        VALUES (?, ?, ?, ?, ?, ?)
      `, [
        monthData.year,
        monthData.month,
        monthData.rx,
        monthData.tx,
        monthData.timestamp,
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