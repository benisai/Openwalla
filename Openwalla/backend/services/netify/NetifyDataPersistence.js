
const { v4: uuidv4 } = require('uuid');
const { databases } = require('../../database/database');
const TimeUtils = require('../../utils/timeUtils');

class NetifyDataPersistence {
  async saveFlow(flowData, deviceInfo = {}) {
    try {
      if (!flowData) return;

      const sql = `
        INSERT INTO flow (
          timeinsert,
          hostname,
          local_ip,
          local_mac,
          fqdn,
          dest_ip,
          dest_port,
          dest_type,
          detected_protocol_name,
          detected_app_name,
          interface,
          internal,
          ndpi_risk_score,
          ndpi_risk_score_client,
          ndpi_risk_score_server,
          client_sni,
          category_application,
          category_domain,
          category_protocol,
          detected_application,
          detected_protocol,
          detection_guessed,
          dns_host_name,
          host_server_name,
          digest
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;

      const params = [
        flowData.timeinsert,
        deviceInfo.hostname || '',
        flowData.local_ip,
        flowData.local_mac,
        flowData.fqdn,
        flowData.dest_ip,
        flowData.dest_port,
        flowData.dest_type,
        flowData.detected_protocol_name,
        flowData.detected_app_name,
        flowData.interface,
        flowData.internal,
        flowData.ndpi_risk_score,
        flowData.ndpi_risk_score_client,
        flowData.ndpi_risk_score_server,
        flowData.client_sni,
        flowData.category_application,
        flowData.category_domain,
        flowData.category_protocol,
        flowData.detected_application,
        flowData.detected_protocol,
        flowData.detection_guessed,
        flowData.dns_host_name,
        flowData.host_server_name,
        flowData.digest
      ];

      return new Promise((resolve, reject) => {
        databases.flows.run(sql, params, (error) => {
          if (error) {
            console.error('[NetifyDataPersistence] Error saving flow:', error);
            reject(error);
          } else {
            resolve();
          }
        });
      });
    } catch (error) {
      console.error('[NetifyDataPersistence] Error in saveFlow:', error);
      throw error;
    }
  }

  async saveStatsPurge(data) {
    try {
      const sql = `
        INSERT INTO stats_purge (
          timeinsert,
          type,
          digest,
          detection_packets,
          last_seen_at,
          local_bytes,
          local_packets,
          other_bytes,
          other_packets,
          total_bytes,
          total_packets,
          interface,
          internal,
          reason
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;

      const params = [
        data.timeinsert,
        data.type,
        data.digest,
        data.detection_packets,
        data.last_seen_at,
        data.local_bytes,
        data.local_packets,
        data.other_bytes,
        data.other_packets,
        data.total_bytes,
        data.total_packets,
        data.interface,
        data.internal,
        data.reason
      ];

      return new Promise((resolve, reject) => {
        databases.flows.run(sql, params, (error) => {
          if (error) {
            console.error('[NetifyDataPersistence] Error saving stats/purge:', error);
            reject(error);
          } else {
            resolve();
          }
        });
      });
    } catch (error) {
      console.error('[NetifyDataPersistence] Error in saveStatsPurge:', error);
      throw error;
    }
  }

  saveNotification(message, severity = 'error', type = 'netify_connection') {
    const sql = `
      INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
      VALUES (?, ?, ?, ?, ?, ?)
    `;
    
    const params = [
      uuidv4(),
      severity,
      type,
      message,
      TimeUtils.getUnixTimestampMs(),
      'none'
    ];

    return new Promise((resolve, reject) => {
      databases.notifications.run(sql, params, (error) => {
        if (error) {
          console.error('[NetifyDataPersistence] Error saving notification:', error);
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }
}

module.exports = NetifyDataPersistence;
