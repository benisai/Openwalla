const { v4: uuidv4 } = require('uuid');
const { databases } = require('../../database/database');

class NetworkNotificationManager {
  static saveNotification(message, severity) {
    const sql = `
      INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
      VALUES (?, ?, ?, ?, ?, ?)
    `;
    
    const params = [
      uuidv4(),
      severity,
      'internet_monitor',
      message,
      Date.now(),
      'none'
    ];

    databases.notifications.run(sql, params, (error) => {
      if (error) {
        console.error('Error saving notification:', error);
      }
    });
  }
}

module.exports = NetworkNotificationManager;