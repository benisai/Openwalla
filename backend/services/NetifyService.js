const net = require('net');
const { v4: uuidv4 } = require('uuid');
const { databases } = require('../database');

class NetifyService {
  constructor(host = '192.168.1.1', port = 7150) {
    this.host = host;
    this.port = port;
    this.client = null;
    this.reconnectAttempts = 0;
    this.MAX_RECONNECT_ATTEMPTS = 30;
    this.RECONNECT_DELAY = 5000;
    this.deviceCache = new Map();
    this.CACHE_REFRESH_INTERVAL = 5 * 60 * 1000; // 5 minutes
  }

  async loadDeviceCache() {
    const sql = `
      SELECT mac, hostname, ip
      FROM clients
    `;
    
    return new Promise((resolve, reject) => {
      databases.devices.all(sql, [], (err, rows) => {
        if (err) {
          console.error('Error loading device cache:', err);
          reject(err);
        } else {
          this.deviceCache.clear();
          rows.forEach(row => {
            this.deviceCache.set(row.mac.toLowerCase(), {
              hostname: row.hostname,
              ip: row.ip
            });
          });
          resolve();
        }
      });
    });
  }

  startCacheRefresh() {
    this.loadDeviceCache();
    setInterval(() => {
      this.loadDeviceCache();
    }, this.CACHE_REFRESH_INTERVAL);
  }

  connect() {
    console.log(`[NetifyService] Connecting to agent at ${this.host}:${this.port}`);
    
    this.startCacheRefresh();
    
    this.client = new net.Socket();

    this.client.connect(this.port, this.host, () => {
      console.log('[NetifyService] Successfully connected to agent');
      this.reconnectAttempts = 0;
    });

    this.client.on('data', (data) => {
      const lines = data.toString().split('\n');
      
      lines.forEach(line => {
        if (line.trim()) {
          try {
            const flowData = JSON.parse(line);
            if (
              flowData.type === 'flow' &&
              flowData.flow.detected_protocol_name &&
              ['DNS', 'HTTPS', 'HTTP'].includes(flowData.flow.detected_protocol_name)
            ) {
              this.saveFlow(flowData);
            }
          } catch (error) {
            // Silently ignore JSON parsing errors as they're likely just incomplete chunks
            if (!(error instanceof SyntaxError)) {
              console.error('[NetifyService] Unexpected error processing flow data:', error);
            }
          }
        }
      });
    });

    this.client.on('error', (error) => {
      console.error('[NetifyService] Connection error:', error.message);
      
      if (this.reconnectAttempts < this.MAX_RECONNECT_ATTEMPTS) {
        this.reconnectAttempts++;
        console.log(`[NetifyService] Reconnection attempt ${this.reconnectAttempts} of ${this.MAX_RECONNECT_ATTEMPTS}`);
        setTimeout(() => this.connect(), this.RECONNECT_DELAY);
      } else {
        console.error('[NetifyService] Max reconnection attempts reached');
        const errorMessage = `Failed to connect to Netify agent after ${this.MAX_RECONNECT_ATTEMPTS} attempts`;
        this.saveNotification(errorMessage);
      }
    });

    this.client.on('close', () => {
      console.log('[NetifyService] Connection closed');
    });
  }

  getDeviceInfo(mac) {
    const cachedDevice = this.deviceCache.get(mac.toLowerCase());
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
          console.error('[NetifyService] Error getting device info:', err);
          reject(err);
        } else {
          const deviceInfo = row || { hostname: '', ip: '' };
          this.deviceCache.set(mac.toLowerCase(), deviceInfo);
          resolve(deviceInfo);
        }
      });
    });
  }

  async saveFlow(flowData) {
    try {
      const deviceInfo = await this.getDeviceInfo(flowData.flow.local_mac);

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

      databases.flows.run(sql, params, (error) => {
        if (error) {
          console.error('[NetifyService] Error saving flow:', error);
        }
      });
    } catch (error) {
      console.error('[NetifyService] Error in saveFlow:', error);
    }
  }

  saveNotification(message) {
    const sql = `
      INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
      VALUES (?, ?, ?, ?, ?, ?)
    `;
    
    const params = [
      uuidv4(),
      'error',
      'netify_connection',
      message,
      Date.now(),
      'none'
    ];

    databases.notifications.run(sql, params, (error) => {
      if (error) {
        console.error('[NetifyService] Error saving notification:', error);
      }
    });
  }

  stop() {
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }
}

module.exports = NetifyService;
