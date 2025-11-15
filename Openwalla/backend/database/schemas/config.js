
module.exports = async function (db, envConfig) {
  const defaultConfig = {
    router_ip: envConfig.router_ip,
    router_protocol: envConfig.router_protocol,
    netify_port: envConfig.netify_port,
    netify_enabled: envConfig.netify_enabled,
    data_plan_limit: envConfig.data_plan_limit,
    hostname: envConfig.hostname,
    openwrt_user: envConfig.openwrt_user,
    openwrt_pass: envConfig.openwrt_pass,
    openwrt_token: '',
    openwrt_token_timestamp: '0',
    luci_port: '',
    ping_address: envConfig.ping_address,
    ping_interval: envConfig.ping_interval,
    retention_days: envConfig.retention_days,
    auth_username: envConfig.auth_username,
    auth_password: envConfig.auth_password,
    ip_lookup_domain: envConfig.ip_lookup_domain,
  };
  
    return new Promise((resolve, reject) => {
      db.run(`
        CREATE TABLE IF NOT EXISTS configs (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      `, [], (err) => {
        if (err) return reject(err);
  
        // Insert default config values if they don't exist
        const stmt = db.prepare(
          'INSERT OR IGNORE INTO configs (key, value) VALUES (?, ?)'
        );
  
        Object.entries(defaultConfig).forEach(([key, value]) => {
          stmt.run(key, String(value), (err) => {
            if (err) console.error(`Error inserting default config ${key}:`, err);
          });
        });
  
        stmt.finalize((err) => {
          if (err) reject(err);
          else resolve();
        });
      });
    });
  };
