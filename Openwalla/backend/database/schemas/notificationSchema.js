const { databases } = require('../connections');

async function initializeNotificationSchema() {
  return new Promise((resolve, reject) => {
    databases.notifications.run(`
      CREATE TABLE IF NOT EXISTS notifications (
        uuid TEXT PRIMARY KEY,
        sev TEXT,
        type TEXT,
        msg TEXT,
        detect_time INTEGER,
        action TEXT
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

module.exports = { initializeNotificationSchema };