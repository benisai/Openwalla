const net = require('net');
const { v4: uuidv4 } = require('uuid');
const { databases } = require('../database/database');

class NetifyService {
  constructor(config) {
    this.host = config.router_ip || '192.168.1.1';
    this.port = parseInt(config.netify_port) || 7150;
    this.client = null;
    this.reconnectAttempts = 0;
    this.MAX_RECONNECT_ATTEMPTS = 9999;
    this.RECONNECT_DELAY = 5000;
    this.deviceCache = new Map();
    this.CACHE_REFRESH_INTERVAL = 5 * 60 * 1000; // 5 minutes
    this.isShuttingDown = false;
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
    if (this.isShuttingDown) {
      console.log('[NetifyService] Service is shutting down, not reconnecting');
      return;
    }

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
              ['DNS', 'HTTPS', 'HTTP', 'HTTP/S'].includes(flowData.flow.detected_protocol_name)
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
      this.handleReconnection('error');
    });

    this.client.on('close', () => {
      console.log('[NetifyService] Connection closed');
      this.handleReconnection('close');
    });
  }

  handleReconnection(trigger) {
    if (this.isShuttingDown) {
      console.log('[NetifyService] Service is shutting down, not attempting reconnection');
      return;
    }

    if (this.reconnectAttempts < this.MAX_RECONNECT_ATTEMPTS) {
      this.reconnectAttempts++;
      console.log(`[NetifyService] Reconnection attempt ${this.reconnectAttempts} of ${this.MAX_RECONNECT_ATTEMPTS} (triggered by ${trigger})`);
      setTimeout(() => this.connect(), this.RECONNECT_DELAY);
    } else {
      console.error('[NetifyService] Max reconnection attempts reached');
      const errorMessage = `Failed to connect to Netify agent after ${this.MAX_RECONNECT_ATTEMPTS} attempts`;
      this.saveNotification(errorMessage);
      
      // Reset reconnection attempts after a longer delay and try again
      setTimeout(() => {
        console.log('[NetifyService] Resetting reconnection attempts and trying again');
        this.reconnectAttempts = 0;
        this.connect();
      }, this.RECONNECT_DELAY * 6); // Wait 30 seconds before starting fresh
    }
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
      
      if (
        flowData.type === 'flow' &&
        flowData.flow.detected_protocol_name &&
        ['DNS', 'HTTPS', 'HTTP/S', 'HTTP'].includes(flowData.flow.detected_protocol_name)
      ) {
        // Standardize HTTP/S to HTTPS
        const standardizedProtocol = flowData.flow.detected_protocol_name === 'HTTP/S' 
          ? 'HTTPS' 
          : flowData.flow.detected_protocol_name;

        // Prioritize client_sni for FQDN if available
        const fqdn = flowData.flow.ssl?.client_sni || flowData.flow.host_server_name || '';

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
            client_sni
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `;

        const params = [
          new Date(flowData.flow.first_seen_at).toISOString(),
          deviceInfo.hostname || '',
          flowData.flow.local_ip,
          flowData.flow.local_mac,
          fqdn,
          flowData.flow.other_ip,
          flowData.flow.other_port,
          'remote',
          standardizedProtocol,
          flowData.flow.detected_application_name || '',
          flowData.interface,
          flowData.internal ? 1 : 0,
          flowData.flow.risks?.ndpi_risk_score || 0,
          flowData.flow.risks?.ndpi_risk_score_client || 0,
          flowData.flow.risks?.ndpi_risk_score_server || 0,
          flowData.flow.ssl?.client_sni || ''
        ];

        databases.flows.run(sql, params, (error) => {
          if (error) {
            console.error('[NetifyService] Error saving flow:', error);
          }
        });
      }
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
    this.isShuttingDown = true;
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }

  // New method to restart the service
  restart() {
    this.isShuttingDown = false;
    this.reconnectAttempts = 0;
    this.stop();
    this.connect();
  }
}

module.exports = NetifyService;
