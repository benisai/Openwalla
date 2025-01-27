const { v4: uuidv4 } = require('uuid');
const { databases } = require('../../database/database');

class NotificationManager {
  saveNotification(message) {
    const sql = `
      INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
      VALUES (?, ?, ?, ?, ?, ?)
    `;
    
    const params = [
      uuidv4(),
      'error',
      'netify_connection',
      message,
      Date.now(),
      'none'
    ];

    return new Promise((resolve, reject) => {
      databases.notifications.run(sql, params, (error) => {
        if (error) {
          console.error('[NotificationManager] Error saving notification:', error);
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }
}

module.exports = NotificationManager;