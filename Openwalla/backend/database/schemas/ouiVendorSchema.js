const axios = require('axios');
const { databases } = require('../connections');

async function initializeOuiVendorSchema() {
  return new Promise((resolve, reject) => {
    databases.ouiVendor.run(`
      CREATE TABLE IF NOT EXISTS oui_vendors (
        oui TEXT PRIMARY KEY,
        vendor TEXT NOT NULL
      )
    `, [], async (err) => {
      if (err) {
        reject(err);
      } else {
        try {
          // Check if table is empty
          const row = await new Promise((resolve, reject) => {
            databases.ouiVendor.get('SELECT COUNT(*) as count FROM oui_vendors', [], (err, row) => {
              if (err) reject(err);
              else resolve(row);
            });
          });

          if (row.count === 0) {
            const response = await axios.get('https://raw.githubusercontent.com/benisai/Openwalla/main/mac-address-oui.json');
            const vendors = response.data;
            
            const stmt = databases.ouiVendor.prepare('INSERT OR REPLACE INTO oui_vendors (oui, vendor) VALUES (?, ?)');
            Object.entries(vendors).forEach(([vendorName, ouis]) => {
              const ouiArray = Array.isArray(ouis) ? ouis : [ouis];
              ouiArray.forEach(oui => {
                stmt.run(oui.toLowerCase(), vendorName);
              });
            });
            stmt.finalize();
          }
          resolve();
        } catch (error) {
          reject(error);
        }
      }
    });
  });
}

module.exports = { initializeOuiVendorSchema };