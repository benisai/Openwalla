const { databases } = require('../../database/database');

class FlowProcessor {
  constructor(deviceCache) {
    this.deviceCache = deviceCache;
  }

  async processFlow(flowData) {
    try {
      const deviceInfo = await this.getDeviceInfo(flowData.flow.local_mac);
      await this.saveFlow(flowData, deviceInfo);
    } catch (error) {
      console.error('[FlowProcessor] Error processing flow:', error);
    }
  }

  async getDeviceInfo(mac) {
    const cachedDevice = this.deviceCache.get(mac);
    if (cachedDevice) {
      return Promise.resolve(cachedDevice);
    }
    
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT hostname, ip
        FROM clients
        WHERE mac = ?
      `;
      
      databases.devices.get(sql, [mac.toLowerCase()], (err, row) => {
        if (err) {
          console.error('[FlowProcessor] Error getting device info:', err);
          reject(err);
        } else {
          const deviceInfo = row || { hostname: '', ip: '' };
          this.deviceCache.set(mac, deviceInfo);
          resolve(deviceInfo);
        }
      });
    });
  }

  async saveFlow(flowData, deviceInfo) {
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
        internal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const params = [
      new Date(flowData.flow.first_seen_at).toISOString(),
      deviceInfo.hostname || '',
      flowData.flow.local_ip,
      flowData.flow.local_mac,
      flowData.flow.host_server_name || '',
      flowData.flow.other_ip,
      flowData.flow.other_port,
      'remote',
      flowData.flow.detected_protocol_name,
      flowData.flow.detected_application_name || '',
      flowData.interface,
      flowData.internal ? 1 : 0
    ];

    return new Promise((resolve, reject) => {
      databases.flows.run(sql, params, (error) => {
        if (error) {
          console.error('[FlowProcessor] Error saving flow:', error);
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }
}

module.exports = FlowProcessor;