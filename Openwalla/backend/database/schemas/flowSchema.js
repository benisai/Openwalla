const { databases } = require('../connections');

async function initializeFlowSchema() {
  return new Promise((resolve, reject) => {
    databases.flows.run(`
      CREATE TABLE IF NOT EXISTS flow (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timeinsert TEXT,
        hostname TEXT,
        local_ip TEXT,
        local_mac TEXT,
        fqdn TEXT,    
        dest_ip TEXT,
        dest_port INTEGER,
        dest_type TEXT,
        detected_protocol_name TEXT,
        detected_app_name TEXT,
        interface TEXT,
        internal INTEGER
      )
    `, [], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

module.exports = { initializeFlowSchema };