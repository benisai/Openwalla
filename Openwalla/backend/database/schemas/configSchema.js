const { databases } = require('../connections');

async function initializeConfigSchema() {
  return new Promise((resolve, reject) => {
    databases.openwalla.run(`
      CREATE TABLE IF NOT EXISTS configs (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    `, [], (err) => {
      if (err) reject(err);
      else {
        const defaultConfigs = Object.entries(require('../../utils/config').getEnvConfig());
        const stmt = databases.openwalla.prepare(
          'INSERT OR IGNORE INTO configs (key, value) VALUES (?, ?)'
        );

        defaultConfigs.forEach(([key, value]) => {
          stmt.run(key, String(value), (err) => {
            if (err) console.error(`Error inserting default config ${key}:`, err);
          });
        });

        stmt.finalize((err) => {
          if (err) reject(err);
          else resolve();
        });
      }
    });
  });
}

module.exports = { initializeConfigSchema };