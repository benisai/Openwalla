const { v4: uuidv4 } = require('uuid');
const { databases } = require('../../database/database');

class PingStatsManager {
  static savePingStats(stats) {
    if (!stats.timestamp || stats.ms === null) {
      console.log('Skipping invalid ping stats:', stats);
      return;
    }

    const sql = `
      INSERT INTO pingstats (
        uuid, ip, ms, max_latency, median_latency, packetloss,
        date, time, timestamp, target_ip, latency, packet_loss,
        status, error_message
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;
    
    const params = [
      stats.uuid,
      stats.ip,
      stats.ms,
      stats.max_latency,
      stats.median_latency,
      stats.packetloss,
      stats.date,
      stats.time,
      stats.timestamp,
      stats.target_ip,
      stats.latency,
      stats.packet_loss,
      stats.status,
      stats.error_message
    ];

    databases.pingStats.run(sql, params, (error) => {
      if (error) {
        console.error('Error saving ping stats:', error);
      }
    });
  }
}

module.exports = PingStatsManager;