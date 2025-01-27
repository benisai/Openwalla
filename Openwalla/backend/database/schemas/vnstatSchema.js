module.exports = async function (db) {
  return new Promise((resolve, reject) => {
    db.serialize(() => {
      db.run(`
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
      `);
      db.run(`
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
      `);
      db.run(`
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
      `, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
};
