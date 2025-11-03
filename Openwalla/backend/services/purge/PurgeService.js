const { databases } = require('../../database/database');

class PurgeService {
  constructor(retentionDays = 7) {
    this.retentionDays = retentionDays;
    this.purgeInterval = null;
  }

  start() {
    console.log(`Starting PurgeService with ${this.retentionDays} days retention`);
    
    // Run immediately on start
    this.runPurge();
    
    // Schedule daily purge at midnight
    this.scheduleMidnightPurge();
  }

  stop() {
    if (this.purgeInterval) {
      clearTimeout(this.purgeInterval);
      this.purgeInterval = null;
    }
  }

  scheduleMidnightPurge() {
    const now = new Date();
    const midnight = new Date(now);
    midnight.setHours(24, 0, 0, 0);
    
    const timeUntilMidnight = midnight.getTime() - now.getTime();
    
    this.purgeInterval = setTimeout(() => {
      this.runPurge();
      // Schedule next midnight purge
      this.scheduleMidnightPurge();
    }, timeUntilMidnight);
    
    console.log(`Next purge scheduled at: ${midnight.toISOString()}`);
  }

  async runPurge() {
    console.log(`Running database purge for data older than ${this.retentionDays} days`);
    
    try {
      await Promise.all([
        this.purgeFlows(),
        this.purgeNotifications(),
        this.purgePingStats(),
        this.purgeVnstat()
      ]);
      
      console.log('Database purge completed successfully');
    } catch (error) {
      console.error('Error during database purge:', error);
    }
  }

  purgeFlows() {
    return new Promise((resolve, reject) => {
      const sql = `DELETE FROM flow WHERE timeinsert < datetime('now', '-${this.retentionDays} days')`;
      
      databases.flows.run(sql, [], function(err) {
        if (err) {
          console.error('Error purging flows:', err);
          reject(err);
        } else {
          console.log(`Purged ${this.changes} flow records`);
          resolve();
        }
      });
    });
  }

  purgeNotifications() {
    return new Promise((resolve, reject) => {
      const retentionTimestamp = Date.now() - (this.retentionDays * 24 * 60 * 60 * 1000);
      const sql = `DELETE FROM notifications WHERE detect_time < ?`;
      
      databases.notifications.run(sql, [retentionTimestamp], function(err) {
        if (err) {
          console.error('Error purging notifications:', err);
          reject(err);
        } else {
          console.log(`Purged ${this.changes} notification records`);
          resolve();
        }
      });
    });
  }

  purgePingStats() {
    return new Promise((resolve, reject) => {
      const retentionTimestamp = Date.now() - (this.retentionDays * 24 * 60 * 60 * 1000);
      const sql = `DELETE FROM pingstats WHERE timestamp < ?`;
      
      databases.pingStats.run(sql, [retentionTimestamp], function(err) {
        if (err) {
          console.error('Error purging ping stats:', err);
          reject(err);
        } else {
          console.log(`Purged ${this.changes} ping stats records`);
          resolve();
        }
      });
    });
  }

  purgeVnstat() {
    return new Promise((resolve, reject) => {
      const retentionTimestamp = Math.floor(Date.now() / 1000) - (this.retentionDays * 24 * 60 * 60);
      const sql = `DELETE FROM hourly WHERE timestamp < ?`;
      
      databases.vnstat.run(sql, [retentionTimestamp], function(err) {
        if (err) {
          console.error('Error purging vnstat hourly data:', err);
          reject(err);
        } else {
          console.log(`Purged ${this.changes} vnstat hourly records`);
          resolve();
        }
      });
    });
  }

  updateRetentionDays(days) {
    this.retentionDays = days;
    console.log(`Updated retention period to ${days} days`);
  }
}

module.exports = PurgeService;
