const { databases } = require('../connections');

async function initializeVnstatSchema() {
  const promises = [];

  // Hourly table
  promises.push(new Promise((resolve, reject) => {
    databases.vnstat.run(`
      CREATE TABLE IF NOT EXISTS hourly (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        hour INTEGER,
        rx INTEGER,
        tx INTEGER,
        timestamp INTEGER,
        interface_name TEXT,
        UNIQUE(year, month, day, hour, interface_name)
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  // Monthly table
  promises.push(new Promise((resolve, reject) => {
    databases.vnstat.run(`
      CREATE TABLE IF NOT EXISTS monthly (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER,
        month INTEGER,
        rx INTEGER,
        tx INTEGER,
        timestamp INTEGER,
        interface_name TEXT,
        UNIQUE(year, month, interface_name)
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  // Daily table
  promises.push(new Promise((resolve, reject) => {
    databases.vnstat.run(`
      CREATE TABLE IF NOT EXISTS daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER,
        month INTEGER,
        day INTEGER,
        rx INTEGER,
        tx INTEGER,
        interface_name TEXT,
        UNIQUE(year, month, day, interface_name)
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  }));

  return Promise.all(promises);
}

module.exports = { initializeVnstatSchema };