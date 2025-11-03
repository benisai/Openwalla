
module.exports = async function initializeUsers(db, config) {
  return new Promise((resolve, reject) => {
    db.run(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `, [], (err) => {
      if (err) return reject(err);

      // Insert default user if it doesn't exist
      const stmt = db.prepare(
        'INSERT OR IGNORE INTO users (username, password) VALUES (?, ?)'
      );

      stmt.run(config.auth_username, config.auth_password, (err) => {
        if (err) console.error('Error inserting default user:', err);
      });

      stmt.finalize((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
};
