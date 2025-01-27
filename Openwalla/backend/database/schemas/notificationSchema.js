/**
 * Notification Schema Definition
 * 
 * Stores system notifications with:
 * - Severity levels
 * - Message types
 * - Detection timestamps
 * - Associated actions
 * 
 * @param {Object} db - SQLite database instance
 * @returns {Promise} Resolves when the notifications table is created
 */
module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.run(`
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
};