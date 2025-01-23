const { databases } = require('../connections');

async function initializeAdblockSchema() {
  return new Promise((resolve, reject) => {
    databases.adblock.serialize(() => {
      // Top Clients table
      databases.adblock.run(`
        CREATE TABLE IF NOT EXISTS adblock_top_clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_ip TEXT NOT NULL,
          query_count INTEGER DEFAULT 0,
          timestamp INTEGER DEFAULT (strftime('%s', 'now')),
          UNIQUE(client_ip)
        )
      `);

      // Top Domains table
      databases.adblock.run(`
        CREATE TABLE IF NOT EXISTS adblock_top_domains (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          domain TEXT NOT NULL,
          query_count INTEGER DEFAULT 0,
          timestamp INTEGER DEFAULT (strftime('%s', 'now')),
          UNIQUE(domain)
        )
      `);

      // Top Blocked Domains table
      databases.adblock.run(`
        CREATE TABLE IF NOT EXISTS adblock_blocked_domains (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          domain TEXT NOT NULL,
          block_count INTEGER DEFAULT 0,
          timestamp INTEGER DEFAULT (strftime('%s', 'now')),
          UNIQUE(domain)
        )
      `);

      // DNS Queries table
      databases.adblock.run(`
        CREATE TABLE IF NOT EXISTS adblock_dns_queries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          query_date TEXT NOT NULL,
          query_time TEXT NOT NULL,
          client_ip TEXT NOT NULL,
          domain TEXT NOT NULL,
          answer TEXT NOT NULL,
          timestamp INTEGER DEFAULT (strftime('%s', 'now'))
        )
      `, [], (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
}

module.exports = { initializeAdblockSchema };