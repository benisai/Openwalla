const axios = require('axios');

module.exports = async function (db, envConfig) {
  return new Promise((resolve, reject) => {
    db.run(`
      CREATE TABLE IF NOT EXISTS oui_vendors (
        oui TEXT PRIMARY KEY,
        vendor TEXT NOT NULL
      )
    `, [], async (err) => {
      if (err) return reject(err);

      // Populate table if empty
      db.get('SELECT COUNT(*) as count FROM oui_vendors', [], async (err, row) => {
        if (err) return reject(err);
        if (row.count === 0) {
          try {
            const response = await axios.get('https://raw.githubusercontent.com/benisai/Openwalla/main/Files/mac-address-oui.json');
            const vendors = response.data;

            const stmt = db.prepare('INSERT OR REPLACE INTO oui_vendors (oui, vendor) VALUES (?, ?)');
            Object.entries(vendors).forEach(([vendorName, ouis]) => {
              const ouiArray = Array.isArray(ouis) ? ouis : [ouis];
              ouiArray.forEach((oui) => {
                stmt.run(oui.toLowerCase(), vendorName);
              });
            });
            stmt.finalize();
            resolve();
          } catch (error) {
            reject(error);
          }
        } else {
          resolve();
        }
      });
    });
  });
};
