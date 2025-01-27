const net = require('net');
const DeviceCache = require('./netify/DeviceCache');
const FlowProcessor = require('./netify/FlowProcessor');
const NotificationManager = require('./netify/NotificationManager');

class NetifyService {
  constructor(config) {
    this.host = config.router_ip || '192.168.1.1';
    this.port = parseInt(config.netify_port) || 7150;
    this.client = null;
    this.reconnectAttempts = 0;
    this.MAX_RECONNECT_ATTEMPTS = 9999;
    this.RECONNECT_DELAY = 5000;
    this.isShuttingDown = false;

    // Initialize supporting services
    this.deviceCache = new DeviceCache();
    this.flowProcessor = new FlowProcessor(this.deviceCache);
    this.notificationManager = new NotificationManager();
  }

  connect() {
    if (this.isShuttingDown) {
      console.log('[NetifyService] Service is shutting down, not reconnecting');
      return;
    }

    console.log(`[NetifyService] Connecting to agent at ${this.host}:${this.port}`);
    
    this.deviceCache.startRefreshInterval();
    
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
              this.flowProcessor.processFlow(flowData);
            }
          } catch (error) {
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
      this.notificationManager.saveNotification(errorMessage);
      
      setTimeout(() => {
        console.log('[NetifyService] Resetting reconnection attempts and trying again');
        this.reconnectAttempts = 0;
        this.connect();
      }, this.RECONNECT_DELAY * 6);
    }
  }

  stop() {
    this.isShuttingDown = true;
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }

  restart() {
    this.isShuttingDown = false;
    this.reconnectAttempts = 0;
    this.stop();
    this.connect();
  }
}

module.exports = NetifyService;